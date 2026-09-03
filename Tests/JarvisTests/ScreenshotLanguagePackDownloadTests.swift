@testable import Jarvis
import XCTest

@MainActor
final class ScreenshotLanguagePackDownloadTests: XCTestCase {
    private struct TestError: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    private enum HandleBehavior {
        case succeed
        case fail(Error)
        case gate
    }

    private final class FakeSessionHandler: LanguagePackSessionHandling, @unchecked Sendable {
        private(set) var prepareCallCount = 0
        private(set) var cancelled = false
        let behavior: HandleBehavior
        private var gateContinuation: CheckedContinuation<Void, Error>?

        init(behavior: HandleBehavior) {
            self.behavior = behavior
        }

        func prepare() async throws {
            prepareCallCount += 1
            switch behavior {
            case .succeed:
                return
            case let .fail(error):
                throw error
            case .gate:
                try await withCheckedThrowingContinuation { continuation in
                    gateContinuation = continuation
                }
            }
        }

        func cancel() {
            cancelled = true
            resumeGate(throwing: CancellationError())
        }

        func release() {
            resumeGate(throwing: nil)
        }

        private func resumeGate(throwing error: Error?) {
            guard let gateContinuation else {
                return
            }
            self.gateContinuation = nil
            if let error {
                gateContinuation.resume(throwing: error)
            } else {
                gateContinuation.resume()
            }
        }
    }

    private final class FakeLanguagePackService: LanguagePackService, @unchecked Sendable {
        var statusResult: LanguagePackSupport = .supported
        var statusDelayNanoseconds: UInt64 = 0
        private(set) var statusCallCount = 0

        func status(for _: ScreenshotTranslationLanguage) async -> LanguagePackSupport {
            statusCallCount += 1
            if statusDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: statusDelayNanoseconds)
            }
            return statusResult
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("waitUntil 超时")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func supportedModel(service: FakeLanguagePackService) async -> LanguagePackRowModel {
        let model = LanguagePackRowModel(target: .english, service: service)
        await model.refresh()
        XCTAssertEqual(model.phase, .supported)
        return model
    }

    private func startGatedDownload(
        model: LanguagePackRowModel,
        handler: FakeSessionHandler
    ) async -> Task<Void, Never> {
        model.startDownload()
        let running = Task { await model.consumeSession(handler) }
        await waitUntil { handler.prepareCallCount == 1 }
        return running
    }

    func testDownloadSuccessTransitionsToInstalled() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .succeed)

        service.statusResult = .installed
        model.startDownload()
        XCTAssertEqual(model.phase, .downloading)
        XCTAssertNotNil(model.sessionConfiguration)
        await model.consumeSession(handler)

        XCTAssertEqual(model.phase, .installed)
        XCTAssertEqual(handler.prepareCallCount, 1)
        XCTAssertFalse(handler.cancelled)
        XCTAssertNil(model.sessionConfiguration, "完成后会话配置应清空")
    }

    func testCancelResetsImmediatelyAndAllowsRedownload() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let first = FakeSessionHandler(behavior: .gate)

        let running = await startGatedDownload(model: model, handler: first)
        XCTAssertEqual(model.phase, .downloading)

        model.cancelDownload()
        XCTAssertNotEqual(model.phase, .downloading, "取消必须立即离开下载中，不等框架中断")
        XCTAssertNil(model.sessionConfiguration)
        XCTAssertTrue(first.cancelled)
        await running.value

        await waitUntil { model.phase == .supported }
        XCTAssertEqual(service.statusCallCount, 2)

        let second = FakeSessionHandler(behavior: .succeed)
        service.statusResult = .installed
        model.startDownload()
        await model.consumeSession(second)
        XCTAssertEqual(model.phase, .installed)
        XCTAssertEqual(second.prepareCallCount, 1)
    }

    func testLateCompletionAfterCancelIsDiscarded() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        let running = await startGatedDownload(model: model, handler: handler)
        model.cancelDownload()
        await waitUntil { model.phase == .supported }

        service.statusResult = .installed
        handler.release()
        await running.value
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.phase, .supported, "迟到的旧 prepare 结果不得覆盖复位后的状态")
    }

    func testConsumeSessionAfterCancelStartsNoWork() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let lateHandler = FakeSessionHandler(behavior: .succeed)

        model.startDownload()
        model.cancelDownload()
        await waitUntil { model.phase == .supported }
        await model.consumeSession(lateHandler)

        XCTAssertEqual(lateHandler.prepareCallCount, 0, "迟到交接不得启动下载")
        XCTAssertEqual(model.phase, .supported)
    }

    func testRepeatedCancelIsIdempotent() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        let running = await startGatedDownload(model: model, handler: handler)
        model.cancelDownload()
        XCTAssertEqual(model.phase, .checking)
        model.cancelDownload()
        model.cancelDownload()
        await running.value

        await waitUntil { model.phase == .supported }
        XCTAssertEqual(service.statusCallCount, 2, "重复取消不应产生额外检测")
        XCTAssertEqual(handler.prepareCallCount, 1)
        XCTAssertEqual(model.phase, .supported)
    }

    func testPrepareFailureMapsToFailedAndAllowsRetry() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)

        model.startDownload()
        await model.consumeSession(FakeSessionHandler(behavior: .fail(TestError(message: "boom"))))
        XCTAssertEqual(model.phase, .failed("boom"))

        let retry = FakeSessionHandler(behavior: .succeed)
        service.statusResult = .installed
        model.startDownload()
        await model.consumeSession(retry)
        XCTAssertEqual(model.phase, .installed)
        XCTAssertEqual(retry.prepareCallCount, 1)
    }

    func testCannotDownloadIssueShowsReadableMessage() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let message = "系统当前无法下载语言包，可在首次截图翻译时由系统自动下载"

        model.startDownload()
        await model.consumeSession(FakeSessionHandler(behavior: .fail(
            LanguagePackDownloadIssue(message: message)
        )))
        XCTAssertEqual(model.phase, .failed(message))
    }

    func testTwoModelsRunInParallelAndCancelIndependently() async {
        let serviceA = FakeLanguagePackService()
        let serviceB = FakeLanguagePackService()
        let modelA = await supportedModel(service: serviceA)
        let modelB = await supportedModel(service: serviceB)
        let handlerA = FakeSessionHandler(behavior: .gate)
        let handlerB = FakeSessionHandler(behavior: .succeed)

        serviceB.statusResult = .installed
        let runningA = await startGatedDownload(model: modelA, handler: handlerA)
        modelB.startDownload()
        await modelB.consumeSession(handlerB)
        XCTAssertEqual(modelA.phase, .downloading)
        XCTAssertEqual(modelB.phase, .installed)

        modelA.cancelDownload()
        await runningA.value
        await waitUntil { modelA.phase == .supported }

        XCTAssertFalse(handlerB.cancelled, "B 的下载不受 A 取消影响")
    }

    func testRefreshDoesNotInterruptDownloading() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let callsBeforeDownload = service.statusCallCount
        let handler = FakeSessionHandler(behavior: .gate)

        let running = await startGatedDownload(model: model, handler: handler)
        await model.refresh()

        XCTAssertEqual(model.phase, .downloading)
        XCTAssertEqual(service.statusCallCount, callsBeforeDownload, "下载中 refresh 不应发起检测")
        model.cancelDownload()
        await running.value
        await waitUntil { model.phase == .supported }
    }

    func testRapidCancelRedownloadLoopStaysStable() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)

        for _ in 0 ..< 20 {
            let handler = FakeSessionHandler(behavior: .gate)
            let running = await startGatedDownload(model: model, handler: handler)
            XCTAssertEqual(model.phase, .downloading)
            model.cancelDownload()
            await running.value
            await waitUntil { model.phase == .supported }
        }
        XCTAssertEqual(model.phase, .supported, "循环后应稳定回到可下载，而不是卡在 downloading")
        XCTAssertNil(model.sessionConfiguration)
    }

    func testInitialStatesAndNoopStarts() async {
        let installedService = FakeLanguagePackService()
        installedService.statusResult = .installed
        let installedModel = LanguagePackRowModel(target: .japanese, service: installedService)
        await installedModel.refresh()
        XCTAssertEqual(installedModel.phase, .installed)
        installedModel.startDownload()
        XCTAssertNil(installedModel.sessionConfiguration)
        XCTAssertEqual(installedModel.phase, .installed)

        let unsupportedService = FakeLanguagePackService()
        unsupportedService.statusResult = .unsupported
        let unsupportedModel = LanguagePackRowModel(target: .korean, service: unsupportedService)
        await unsupportedModel.refresh()
        XCTAssertEqual(unsupportedModel.phase, .unsupported)
        unsupportedModel.startDownload()
        XCTAssertNil(unsupportedModel.sessionConfiguration)

        let gatedService = FakeLanguagePackService()
        let gatedModel = await supportedModel(service: gatedService)
        gatedModel.startDownload()
        XCTAssertEqual(gatedModel.phase, .downloading)
        gatedModel.startDownload()
        gatedModel.cancelDownload()
        await waitUntil { gatedModel.phase == .supported }
    }

    func testTearDownCancelsHandleAndStopsWrites() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        let running = await startGatedDownload(model: model, handler: handler)
        model.tearDown()
        XCTAssertTrue(handler.cancelled)
        XCTAssertNil(model.sessionConfiguration)

        service.statusResult = .installed
        handler.release()
        await running.value
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.phase, .downloading, "tearDown 后旧任务不得再写状态")
    }
}

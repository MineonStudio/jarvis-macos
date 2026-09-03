@testable import Jarvis
import XCTest

// 状态机模型测试：注入可控假服务/假会话句柄，不触真实 Translation 框架。
// 覆盖下载成功、取消立即复位、迟到写丢弃、会话通道竞态、并行互不影响、快速取消循环等
@MainActor
final class ScreenshotLanguagePackDownloadTests: XCTestCase {
    private struct TestError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private enum HandleBehavior {
        case succeed
        case fail(Error)
        case gate // 阻塞直到 cancel()/release() 放行
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
            gateContinuation?.resume(throwing: CancellationError())
            gateContinuation = nil
        }

        func release() {
            gateContinuation?.resume()
            gateContinuation = nil
        }
    }

    private final class FakeLanguagePackService: LanguagePackService, @unchecked Sendable {
        var statusResult: LanguagePackSupport = .supported
        // 每次 status 调用延迟，用于制造"迟到检测"竞争窗口
        var statusDelayNanoseconds: UInt64 = 0
        private(set) var statusCallCount = 0

        func status(for target: ScreenshotTranslationLanguage) async -> LanguagePackSupport {
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

    // 1. 下载成功 → installed；句柄 prepare 恰一次
    func testDownloadSuccessTransitionsToInstalled() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .succeed)

        service.statusResult = .installed // prepare 成功后的复核
        model.startDownload()
        XCTAssertEqual(model.phase, .downloading)
        XCTAssertNotNil(model.sessionConfiguration)
        model.handOver(handler)

        await waitUntil { model.phase == .installed }
        XCTAssertEqual(handler.prepareCallCount, 1)
        XCTAssertFalse(handler.cancelled)
        XCTAssertNil(model.sessionConfiguration, "完成后会话配置应清空")
    }

    // 2. 取消立即复位（prepare 阻塞中），可再次下载并成功
    func testCancelResetsImmediatelyAndAllowsRedownload() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let first = FakeSessionHandler(behavior: .gate)

        model.startDownload()
        model.handOver(first)
        XCTAssertEqual(model.phase, .downloading)

        model.cancelDownload()
        XCTAssertNotEqual(model.phase, .downloading, "取消必须立即离开下载中，不等框架中断")
        XCTAssertNil(model.sessionConfiguration)
        XCTAssertTrue(first.cancelled)

        await waitUntil { model.phase == .supported }
        XCTAssertEqual(service.statusCallCount, 2) // 初始 refresh + 取消后复检

        let second = FakeSessionHandler(behavior: .succeed)
        service.statusResult = .installed
        model.startDownload()
        model.handOver(second)
        await waitUntil { model.phase == .installed }
        XCTAssertEqual(second.prepareCallCount, 1)
    }

    // 3. 取消后旧 prepare 迟到完成 → 结果被代数守卫丢弃，不得变 installed
    func testLateCompletionAfterCancelIsDiscarded() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        model.startDownload()
        model.handOver(handler)
        model.cancelDownload()
        await waitUntil { model.phase == .supported }

        service.statusResult = .installed
        handler.release() // 旧任务此时才"完成"
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.phase, .supported, "迟到的旧 prepare 结果不得覆盖复位后的状态")
    }

    // 4. 会话到达晚于取消：迟到交接不得启动任何工作（translationTask 通道竞态）
    func testHandOverAfterCancelStartsNoWork() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let lateHandler = FakeSessionHandler(behavior: .succeed)

        model.startDownload()
        model.cancelDownload() // 会话尚未到达就取消
        await waitUntil { model.phase == .supported }
        model.handOver(lateHandler) // 迟到的旧会话交接

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(lateHandler.prepareCallCount, 0, "迟到交接不得启动下载")
        XCTAssertEqual(model.phase, .supported)
    }

    // 5. 重复取消幂等：第二次取消不产生额外检测，终态稳定
    func testRepeatedCancelIsIdempotent() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        model.startDownload()
        model.handOver(handler)
        model.cancelDownload()
        XCTAssertEqual(model.phase, .checking)
        model.cancelDownload() // 二次取消 no-op
        model.cancelDownload()

        await waitUntil { model.phase == .supported }
        XCTAssertEqual(service.statusCallCount, 2, "重复取消不应产生额外检测")
        XCTAssertEqual(handler.prepareCallCount, 1)
        XCTAssertEqual(model.phase, .supported)
    }

    // 6. prepare 真实错误 → failed(含文案)；failed 可重试
    func testPrepareFailureMapsToFailedAndAllowsRetry() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)

        model.startDownload()
        model.handOver(FakeSessionHandler(behavior: .fail(TestError(message: "boom"))))
        await waitUntil { model.phase == .failed("boom") }

        let retry = FakeSessionHandler(behavior: .succeed)
        service.statusResult = .installed
        model.startDownload()
        model.handOver(retry)
        await waitUntil { model.phase == .installed }
        XCTAssertEqual(retry.prepareCallCount, 1)
    }

    // 7. 系统禁止下载的可读文案（LanguagePackDownloadIssue）不被误判为取消
    func testCannotDownloadIssueShowsReadableMessage() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)

        model.startDownload()
        model.handOver(FakeSessionHandler(behavior: .fail(
            LanguagePackDownloadIssue(message: "系统当前无法下载语言包，可在首次截图翻译时由系统自动下载")
        )))
        await waitUntil {
            if case .failed(let message) = model.phase {
                return message.contains("自动下载")
            }
            return false
        }
    }

    // 8. 两个模型并行：取消 A 不影响 B 完成
    func testTwoModelsRunInParallelAndCancelIndependently() async {
        let serviceA = FakeLanguagePackService()
        let serviceB = FakeLanguagePackService()
        let modelA = await supportedModel(service: serviceA)
        let modelB = await supportedModel(service: serviceB)
        let handlerA = FakeSessionHandler(behavior: .gate)
        let handlerB = FakeSessionHandler(behavior: .succeed)

        serviceB.statusResult = .installed // 刷新后再切换，B 下载成功后的复核返回 installed
        modelA.startDownload()
        modelA.handOver(handlerA)
        modelB.startDownload()
        modelB.handOver(handlerB)
        XCTAssertEqual(modelA.phase, .downloading)
        XCTAssertEqual(modelB.phase, .downloading)

        modelA.cancelDownload()
        await waitUntil { modelB.phase == .installed }
        await waitUntil { modelA.phase == .supported }

        XCTAssertFalse(handlerB.cancelled, "B 的下载不受 A 取消影响")
    }

    // 9. refresh 不打断下载中（v2 教训回归）
    func testRefreshDoesNotInterruptDownloading() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let callsBeforeDownload = service.statusCallCount

        model.startDownload()
        model.handOver(FakeSessionHandler(behavior: .gate))
        await model.refresh()

        XCTAssertEqual(model.phase, .downloading)
        XCTAssertEqual(service.statusCallCount, callsBeforeDownload, "下载中 refresh 不应发起检测")
        model.cancelDownload()
        await waitUntil { model.phase == .supported }
    }

    // 10. 快速 下载/取消 循环：无卡死，终态稳定可再次下载（取消后需等复位到 supported——UI 上按钮此时才出现）
    func testRapidCancelRedownloadLoopStaysStable() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)

        for _ in 0 ..< 20 {
            model.startDownload()
            XCTAssertEqual(model.phase, .downloading)
            model.handOver(FakeSessionHandler(behavior: .gate))
            model.cancelDownload()
            await waitUntil { model.phase == .supported }
        }
        XCTAssertEqual(model.phase, .supported, "循环后应稳定回到可下载，而不是卡在 downloading")
        XCTAssertNil(model.sessionConfiguration)
    }

    // 11. installed/unsupported 初始态正确；checking/downloading 下 startDownload 为 no-op
    func testInitialStatesAndNoopStarts() async {
        let installedService = FakeLanguagePackService()
        installedService.statusResult = .installed
        let installedModel = LanguagePackRowModel(target: .japanese, service: installedService)
        await installedModel.refresh()
        XCTAssertEqual(installedModel.phase, .installed)
        installedModel.startDownload() // no-op
        XCTAssertNil(installedModel.sessionConfiguration)
        XCTAssertEqual(installedModel.phase, .installed)

        let unsupportedService = FakeLanguagePackService()
        unsupportedService.statusResult = .unsupported
        let unsupportedModel = LanguagePackRowModel(target: .korean, service: unsupportedService)
        await unsupportedModel.refresh()
        XCTAssertEqual(unsupportedModel.phase, .unsupported)
        unsupportedModel.startDownload() // no-op
        XCTAssertNil(unsupportedModel.sessionConfiguration)

        let gatedService = FakeLanguagePackService()
        let gatedModel = await supportedModel(service: gatedService)
        gatedModel.startDownload()
        XCTAssertEqual(gatedModel.phase, .downloading)
        gatedModel.startDownload() // downloading 下 no-op
        gatedModel.cancelDownload()
        await waitUntil { gatedModel.phase == .supported }
    }

    // 12. tearDown 取消句柄与任务，不再产生状态写入
    func testTearDownCancelsHandleAndStopsWrites() async {
        let service = FakeLanguagePackService()
        let model = await supportedModel(service: service)
        let handler = FakeSessionHandler(behavior: .gate)

        model.startDownload()
        model.handOver(handler)
        model.tearDown()
        XCTAssertTrue(handler.cancelled)
        XCTAssertNil(model.sessionConfiguration)

        service.statusResult = .installed
        handler.release()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.phase, .downloading, "tearDown 后旧任务不得再写状态")
    }
}

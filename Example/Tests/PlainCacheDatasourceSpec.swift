@testable import DataSourcerer
import Foundation
import Nimble
import Quick

class PlainCacheDatasourceSpec: QuickSpec {

    private lazy var testStringLoadImpulse = LoadImpulse(parameters: "1")

    private lazy var testStringState: State<String, String, TestDatasourceError> = {
        return State(
            provisioningState: .result,
            loadImpulse: testStringLoadImpulse,
            value: EquatableBox("1"),
            error: nil
        )
    }()

    private func testDatasource(persistedState: State<String, String, TestDatasourceError>)
        -> PlainCacheDatasource<String, String, TestDatasourceError> {

        let persister = TestStatePersister<String, String, TestDatasourceError>()
        persister.persist(persistedState)

        let loadImpulseEmitter = DefaultLoadImpulseEmitter<String>(emitOnFirstObservation: persistedState.loadImpulse)
        return PlainCacheDatasource<String, String, TestDatasourceError>(
            persister: persister.any,
            loadImpulseEmitter: loadImpulseEmitter.any,
            cacheLoadError: TestDatasourceError.cacheCouldNotLoad(.default)
        )
    }

    override func spec() {
        describe("PlainCacheDatasourceSpec") {
            it("should send stored value synchronously if initial load impulse is set") {

                let datasource = self.testDatasource(persistedState: self.testStringState)
                var observedStates: [State<String, String, TestDatasourceError>] = []

                let disposable = datasource.observe({ state in
                    observedStates.append(state)
                })

                disposable.dispose()

                expect(observedStates) == [State<String, String, TestDatasourceError>.notReady,
                                           self.testStringState]
            }
            it("should release observer after disposal") {

                let datasource = self.testDatasource(persistedState: self.testStringState)

                weak var testStr: NSMutableString?

                let testScope: () -> Disposable = {
                    let innerStr = NSMutableString(string: "")
                    let disposable = datasource.observe({ state in
                        if let value = state.value?.value {
                            innerStr.append(value)
                        }
                    })
                    testStr = innerStr
                    return disposable
                }

                let disposable = testScope()
                expect(testStr) == "1"

                datasource.loadImpulseEmitter.emit(LoadImpulse(parameters: "1"))
                expect(testStr) == "11"

                disposable.dispose()

                // Force sync access to observers so next assert works synchronously.
                // Alternatively, a wait or waitUntil could be used, but this is
                // less complex.
                datasource.loadImpulseEmitter.emit(LoadImpulse(parameters: "1"))

                expect(testStr).to(beNil())
            }
        }
    }

}
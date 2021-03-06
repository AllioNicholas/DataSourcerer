import Foundation
import DataSourcerer

struct ChatBotTableItemModelsProducer {

    func make()
        -> ItemModelsProducer
        <PostInitialLoadChatBotState, InitialChatBotRequest, APIError, ChatBotCell, NoSection> {

            return ItemModelsProducer(baseValueToListViewStateTransformer: valueToListViewStateTransformer())
    }

    private func valueToListViewStateTransformer()
        -> ValueToListViewStateTransformer
        <PostInitialLoadChatBotState, InitialChatBotRequest, APIError, ChatBotCell, NoSection> {
            return ValueToListViewStateTransformer { value, resourceState
                -> ListViewState
                <PostInitialLoadChatBotState, InitialChatBotRequest, APIError, ChatBotCell, NoSection> in

                let initialRequestProvisioningState = resourceState.provisioningState
                switch initialRequestProvisioningState {
                case .notReady:
                    return .notReady
                case .loading, .result:
                    let oldMessages = value.oldMessagesState.value?.value.messages ?? []
                    let initialMessages = value.initialLoadResponse.messages
                    let newMessages = value.newMessagesState.value?.value.messages ?? []
                    let allMessages = oldMessages + initialMessages + newMessages
                    var allCells = allMessages.map { ChatBotCell.message($0) }

                    // Add loading old messages cell if result is shown.
                    // Later on, hide loading cell if no more old messages available.
                    if case .result = initialRequestProvisioningState {
                        allCells = [ChatBotCell.oldMessagesLoading] + allCells
                    }

                    let sectionAndItems = SectionAndItems(NoSection(), allCells)
                    return ListViewState.readyToDisplay(resourceState, [sectionAndItems])
                }
            }
    }
}

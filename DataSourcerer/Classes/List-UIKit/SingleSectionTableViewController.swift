import Dwifft
import Foundation

open class SingleSectionTableViewController
    <Value: Equatable, P: ResourceParams, E, CellModelType: ItemModel, HeaderItem: SupplementaryItemModel,
    HeaderItemError, FooterItem: SupplementaryItemModel, FooterItemError>
    : UIViewController
    where CellModelType.E == E, HeaderItem.E == HeaderItemError, FooterItem.E == FooterItemError {

    public typealias ValuesObservable = AnyObservable<Value>
    public typealias ViewState = SingleSectionListViewState<Value, P, E, CellModelType>
    public typealias Configuration = ListViewDatasourceConfiguration
        <Value, P, E, CellModelType, UITableViewCell, NoSection, HeaderItem, UIView, HeaderItemError,
        FooterItem, UIView, FooterItemError, UITableView>
    public typealias ChangeCellsInView = (UITableView, _ previous: ViewState, _ next: ViewState) -> Void

    open var refreshControl: UIRefreshControl?
    private let disposeBag = DisposeBag()

    public lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: self.tableViewStyle)
        self.view.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        view.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        let footerView = UIView(frame: .zero)
        view.tableFooterView = footerView

        return view
    }()

    public var addEmptyViewAboveTableView = true // To prevent tableview insets bugs in iOS10
    public var tableViewStyle = UITableView.Style.plain
    public var estimatedRowHeight: CGFloat = 75
    public var supportPullToRefresh = true
    public var animateTableViewUpdates = true
    public var pullToRefresh: (() -> Void)?
    public var willChangeCellsInView: ChangeCellsInView?
    public var didChangeCellsInView: ChangeCellsInView?

    open var isViewVisible: Bool {
        return viewIfLoaded?.window != nil && view.alpha > 0.001
    }

    private let configuration: Configuration
    public lazy var tableViewDatasource = TableViewDatasource(
        configuration: configuration,
        tableView: tableView
    )

    private var tableViewDiffCalculator: SingleSectionTableViewDiffCalculator<CellModelType>?

    public init(configuration: Configuration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required public init?(coder aDecoder: NSCoder) {
        fatalError("Storyboards cannot be used with this class")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        extendedLayoutIncludesOpaqueBars = true

        if addEmptyViewAboveTableView {
            view.addSubview(UIView())
        }

        tableView.delegate = tableViewDatasource
        tableView.dataSource = tableViewDatasource
        tableView.tableFooterView = UIView(frame: .zero)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = estimatedRowHeight

        if #available(iOS 11.0, *) {
            tableView.insetsContentViewsToSafeArea = true
        }

        if supportPullToRefresh {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(doPullToRefresh), for: .valueChanged)
            tableView.addSubview(refreshControl)
            tableView.sendSubviewToBack(refreshControl)
            self.refreshControl = refreshControl
        }

        let cellsProperty = tableViewDatasource.cellsProperty
        var previousCells = cellsProperty.value

        // Update table with most current cells
        cellsProperty
            .skipRepeats { lhs, rhs -> Bool in
                return lhs.items == rhs.items
            }
            .observe { [weak self] cells in
                self?.updateCells(previous: previousCells, next: cells)
                previousCells = cells
            }
            .disposed(by: disposeBag)
    }

    private func updateCells(previous: ViewState, next: ViewState) {

        switch previous {
        case let .readyToDisplay(_, previousCells) where isViewVisible && animateTableViewUpdates:
            if tableViewDiffCalculator == nil {
                // Use previous cells as initial values such that "next" cells are
                // inserted with animations
                tableViewDiffCalculator = createTableViewDiffCalculator(initial: previousCells)
            }
            willChangeCellsInView?(tableView, previous, next)
            tableViewDiffCalculator?.rows = next.items ?? []
            didChangeCellsInView?(tableView, previous, next)
        case .readyToDisplay, .notReady:
            // Animations disabled or view invisible - skip animations.
            self.tableViewDiffCalculator = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.willChangeCellsInView?(self.tableView, previous, next)
                self.tableView.reloadData()
                self.didChangeCellsInView?(self.tableView, previous, next)
            }
        }
    }

    private func createTableViewDiffCalculator(initial: [CellModelType])
        -> SingleSectionTableViewDiffCalculator<CellModelType> {
            let calculator = SingleSectionTableViewDiffCalculator<CellModelType>(
                tableView: tableView,
                initialRows: initial
            )
            calculator.insertionAnimation = .fade
            calculator.deletionAnimation = .fade
            return calculator
    }

    @objc
    func doPullToRefresh() {
        pullToRefresh?()
    }

    public func onPullToRefresh(_ pullToRefresh: @escaping () -> Void)
        -> SingleSectionTableViewController {

        self.pullToRefresh = pullToRefresh
        return self
    }

}

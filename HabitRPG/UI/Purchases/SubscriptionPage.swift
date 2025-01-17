//
//  SubscriptionPage.swift
//  Habitica
//
//  Created by Phillip Thelen on 16.11.23.
//  Copyright © 2023 HabitRPG Inc. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftyStoreKit
import FirebaseAnalytics
import ReactiveSwift
import Habitica_Models
import SwiftUIX

enum PresentationPoint {
    case armoire
    case faint
    case timetravelers
    case gemForGold
    
    var headerText: String {
        switch self {
        case .armoire:
            return L10n.Subscription.armoreHeader
        case .faint:
            return L10n.Subscription.faintHeader
        case .gemForGold:
            return L10n.Subscription.gemForGoldHeader
        case .timetravelers:
            return L10n.Subscription.hourglassesHeader
        }
    }
}

struct SubscriptionOptionStack: View {
    @ObservedObject var viewModel: SubscriptionViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.presentationPoint != .timetravelers {
                SubscriptionOptionViewUI(price: Text(viewModel.priceFor(PurchaseHandler.subscriptionIdentifiers[0])),
                                         recurring: Text(L10n.subscriptionDuration(L10n.month)),
                                         instantGems: "24",
                                         isSelected: PurchaseHandler.subscriptionIdentifiers[0] == viewModel.selectedSubscription)
            }
            SubscriptionOptionViewUI(price: Text(viewModel.priceFor(PurchaseHandler.subscriptionIdentifiers[1])),
                                     recurring: Text(L10n.subscriptionDuration(L10n.xMonths(3))),
                                     instantGems: "24",
                                     isSelected: PurchaseHandler.subscriptionIdentifiers[1] == viewModel.selectedSubscription)
            if viewModel.presentationPoint == nil {
                SubscriptionOptionViewUI(price: Text(viewModel.priceFor(PurchaseHandler.subscriptionIdentifiers[2])),
                                         recurring: Text(L10n.subscriptionDuration(L10n.xMonths(6))),
                                         instantGems: "24",
                                         isSelected: PurchaseHandler.subscriptionIdentifiers[2] == viewModel.selectedSubscription)
            }
            SubscriptionOptionViewUI(price: Text(viewModel.priceFor(PurchaseHandler.subscriptionIdentifiers[3])), recurring: Text(L10n.subscriptionDuration(L10n.xMonths(12))),
                                     tag: HStack(spacing: 0) {
                Image(uiImage: Asset.flagFlap.image.withRenderingMode(.alwaysTemplate)).foregroundColor(Color(hexadecimal: "77F4C7"))
                Text("Popular").foregroundColor(Color(UIColor.teal1)).font(.system(size: 12, weight: .semibold))
                    .frame(height: 24)
                    .padding(.horizontal, 8)
                    .background(LinearGradient(colors: [
                        Color(hexadecimal: "77F4C7"),
                        Color(hexadecimal: "72CFFF")
                ], startPoint: .leading, endPoint: .trailing))
            },
                                     instantGems: "50",
                                     isSelected: PurchaseHandler.subscriptionIdentifiers[3] == viewModel.selectedSubscription,
                                     nonSalePrice: "$59.99",
                                     gemCapMax: true,
                                     showHourglassPromo: viewModel.showHourglassPromo)
        }
    }
}

class SubscriptionViewModel: ObservableObject {
    private let disposable = ScopedDisposable(CompositeDisposable())

    let appleValidator: AppleReceiptValidator
    let itunesSharedSecret = Secrets.itunesSharedSecret
    let userRepository = UserRepository()
    let inventoryRepository = InventoryRepository()
    
    var onSubscriptionSuccessful: (() -> Void)?
    
    @Published var presentationPoint: PresentationPoint?
    @Published var isSubscribed: Bool = false
    @Published var showHourglassPromo: Bool = true
    @Published var prices = [String: String]()
    @Published var mysteryGear: GearProtocol?
    
    @Published var isSubscribing = false
    @Published var selectedSubscription: String = PurchaseHandler.subscriptionIdentifiers[0]
    @Published var availableSubscriptions = PurchaseHandler.subscriptionIdentifiers
    
    init(presentationPoint: PresentationPoint?) {
        #if DEBUG
            appleValidator = AppleReceiptValidator(service: .production, sharedSecret: itunesSharedSecret)
        #else
            appleValidator = AppleReceiptValidator(service: .production, sharedSecret: itunesSharedSecret)
        #endif
        self.presentationPoint = presentationPoint
        
        if presentationPoint != nil {
            availableSubscriptions.remove(at: 2)
        }
        if presentationPoint == .timetravelers {
            availableSubscriptions.remove(at: 0)
        }
        
        selectedSubscription = PurchaseHandler.subscriptionIdentifiers.last ?? PurchaseHandler.subscriptionIdentifiers[0]
        
        disposable.inner.add(inventoryRepository.getLatestMysteryGear().on(value: { gear in
            self.mysteryGear = gear
        }).start())
        
        retrieveProductList()
    }
    
    func retrieveProductList() {
        SwiftyStoreKit.retrieveProductsInfo(Set(PurchaseHandler.subscriptionIdentifiers)) { (result) in
            var prices = [String: String]()
            for product in result.retrievedProducts {
                prices[product.productIdentifier] = product.localizedPrice
            }
            self.prices = prices
        }
    }
    
    func priceFor(_ identifier: String) -> String {
        return prices[identifier] ?? ""
    }
    
    func subscribeTapped() {
        if !PurchaseHandler.shared.isAllowedToMakePurchases() {
            return
        }
        isSubscribing = true
        SwiftyStoreKit.purchaseProduct(selectedSubscription, atomically: false) { result in
            self.isSubscribing = false
            switch result {
            case .success(let product):
                self.verifyAndSubscribe(product)
                logger.log("Purchase Success: \(product.productId)")
            case .error(let error):
                Analytics.logEvent("purchase_failed", parameters: ["error": error.localizedDescription, "code": error.errorCode])

                logger.log("Purchase Failed: \(error)", level: .error)
            case .deferred:
                return
            }
        }
    }
    
    func verifyAndSubscribe(_ product: PurchaseDetails) {
        SwiftyStoreKit.verifyReceipt(using: appleValidator, forceRefresh: true) { result in
            switch result {
            case .success(let receipt):
                // Verify the purchase of a Subscription
                if self.isValidSubscription(product.productId, receipt: receipt) {
                    self.activateSubscription(product.productId, receipt: receipt) { status in
                        if status {
                            if product.needsFinishTransaction {
                                SwiftyStoreKit.finishTransaction(product.transaction)
                            }
                        }
                        self.dismiss()
                    }
                }
            case .error(let error):
                logger.log("Receipt verification failed: \(error)", level: .error)
            }
        }
    }
    
    private func dismiss() {
        if let action = self.onSubscriptionSuccessful {
            action()
        }
    }
    
    func isSubscription(_ identifier: String) -> Bool {
        return  PurchaseHandler.subscriptionIdentifiers.contains(identifier)
    }

    func isValidSubscription(_ identifier: String, receipt: ReceiptInfo) -> Bool {
        if !isSubscription(identifier) {
            return false
        }
        let purchaseResult = SwiftyStoreKit.verifySubscription(
            ofType: .autoRenewable,
            productId: identifier,
            inReceipt: receipt,
            validUntil: Date()
        )
        switch purchaseResult {
        case .purchased:
            return true
        case .expired:
            return false
        case .notPurchased:
            return false
        }
    }
    
    func activateSubscription(_ identifier: String, receipt: ReceiptInfo, completion: @escaping (Bool) -> Void) {
        if let lastReceipt = receipt["latest_receipt"] as? String {
            userRepository.subscribe(sku: identifier, receipt: lastReceipt).observeResult { (result) in
                switch result {
                case .success:
                    completion(true)
                    self.isSubscribed = true
                case .failure:
                    completion(false)
                }
            }
        }
    }
}

struct SubscriptionSeparator: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill().frame(maxWidth: .infinity).height(1)
            Image(Asset.separatorFancyIcon.name).padding(.vertical, 16).padding(.horizontal, 10)
            Rectangle().fill().frame(maxWidth: .infinity).height(1)
        }.foregroundColor(Color(UIColor.purple400))
    }
}

struct SubscriptionBenefitListView: View {
    let presentationPoint: PresentationPoint?
    let mysteryGear: GearProtocol?
    
    var body: some View {
        if presentationPoint != .gemForGold {
            SubscriptionBenefitView(icon: Image(Asset.subBenefitsGems.name), title: Text(L10n.subscriptionInfo1Title), description: Text(L10n.subscriptionInfo1Description))
        }
        SubscriptionBenefitView(icon: PixelArtView(name: "shop_set_mystery_\(mysteryGear?.key?.split(separator: "_").last ?? "")"), title: Text(L10n.subscriptionInfo3Title),
                                description: Text(L10n.subscriptionInfo3Description))

        if presentationPoint != .timetravelers {
            SubscriptionBenefitView(icon: Image(Asset.subBenefitsHourglasses.name), title: Text(L10n.subscriptionInfo2Title), description: Text(L10n.subscriptionInfo2Description))
        }
        if presentationPoint != .faint {
            SubscriptionBenefitView(icon: Image(Asset.subBenefitsFaint.name), title: Text(L10n.Subscription.infoFaintTitle), description: Text(L10n.Subscription.infoFaintDescription))
        }
        if presentationPoint != .armoire {
            SubscriptionBenefitView(icon: Image(Asset.subBenefitsArmoire.name), title: Text(L10n.Subscription.infoArmoireTitle), description: Text(L10n.Subscription.infoArmoireDescription))
        }
        SubscriptionBenefitView(icon: Image(Asset.subBenefitDrops.name), title: Text(L10n.subscriptionInfo5Title), description: Text(L10n.subscriptionInfo5Description)).padding(.bottom, 16)
    }
}

struct GiftSubscriptionSegment: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(Asset.giftSubGift.name)
            Text(L10n.subscriptionGiftExplanation).multilineTextAlignment(.center)
            HabiticaButtonUI(label: Text(L10n.subscriptionGiftButton), color: .purple200, size: .compact) {
                RouterHandler.shared.handle(.giftSubscription)
            }
        }
    }
}

struct SubscriptionPage: View {
    @ObservedObject var viewModel: SubscriptionViewModel
    
    var backgroundColor: Color = Color(UIColor.purple300)
    var textColor: Color = .white
    
    var body: some View {
            LazyVStack(spacing: 0) {
                if let point = viewModel.presentationPoint {
                    Text(point.headerText)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 24)
                } else {
                    if viewModel.isSubscribed {
                        Image(backgroundColor.uiColor().isLight() ? Asset.subscriberHeader.name : Asset.subscriberHeaderDark.name)
                    } else {
                        Image(backgroundColor.uiColor().isLight() ? Asset.subscribeHeader.name : Asset.subscribeHeaderDark.name)
                    }
                }
                if !viewModel.isSubscribed {
                    Text(L10n.Subscription.stayMotivatedWithMoreRewards)
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 32)
                        .padding(.horizontal, 24)
                    SubscriptionSeparator()
                        .padding(.horizontal, 24)
                    SubscriptionBenefitListView(presentationPoint: viewModel.presentationPoint, mysteryGear: viewModel.mysteryGear)
                        .padding(.horizontal, 24)
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            ForEach(enumerating: viewModel.availableSubscriptions) { sub in
                                Rectangle()
                                    .fill()
                                    .foregroundColor(Color(UIColor.purple200))
                                    .frame(height: viewModel.showHourglassPromo && sub == viewModel.availableSubscriptions.last ? 186 : 126)
                                    .cornerRadius(12)
                                    .padding(.vertical, 4).onTapGesture {
                                        withAnimation {
                                            viewModel.selectedSubscription = sub
                                        }
                                    }
                            }
                        }
                        Rectangle()
                            .frame(height: viewModel.showHourglassPromo && viewModel.selectedSubscription == viewModel.availableSubscriptions.last ? 186 : 126)
                            .cornerRadius(12)
                            .offset(y: 4.0 + (CGFloat(viewModel.availableSubscriptions.firstIndex(of: viewModel.selectedSubscription) ?? 0) * 134.0))
                            .animation(.interpolatingSpring(stiffness: 500, damping: 55), value: viewModel.selectedSubscription)
                        SubscriptionOptionStack(viewModel: viewModel)
                    }
                        .padding(.horizontal, 24)
                    Group {
                        if viewModel.isSubscribing {
                            ProgressView().habiticaProgressStyle().frame(height: 48)
                        } else {
                            HabiticaButtonUI(label: Text(L10n.subscribe).foregroundColor(Color(UIColor.purple100)), color: Color(UIColor.yellow100), size: .compact) {
                                viewModel.subscribeTapped()
                            }
                        }
                    }
                    .padding(.vertical, 13)
                    .padding(.horizontal, 24)
                    Text(L10n.subscriptionSupportDevelopers)
                        .foregroundColor(Color(UIColor.purple600))
                        .font(.system(size: 13))
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    GiftSubscriptionSegment()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 30)
                    Image(Asset.subscriptionBackground.name)
                    SubscriptionDisclaimer()
                } else {
                    Image(Asset.subscriptionBackground.name)
                        .padding(.bottom, 20)
                        .background(.purple400)
                }
            }
            .foregroundColor(textColor)
            .padding(.top, 16)
            .background(backgroundColor.ignoresSafeArea(.all, edges: .top).padding(.bottom, 4))
        .cornerRadius([.topLeading, .topTrailing], 12)
    }
}

struct ScrollableSubscriptionPage: View {
    let viewModel: SubscriptionViewModel
    
    var body: some View {
        ScrollView {
            SubscriptionPage(viewModel: viewModel)
        }
        .background(Color.purple400.ignoresSafeArea(.all, edges: .bottom).padding(.top, 200))
    }
}

struct SubscriptionPagePreview: PreviewProvider {
    static var previews: some View {
        SubscriptionPage(viewModel: SubscriptionViewModel(presentationPoint: nil))
        SubscriptionPage(viewModel: SubscriptionViewModel(presentationPoint: .armoire)).previewDisplayName("Armoire")
        SubscriptionPage(viewModel: SubscriptionViewModel(presentationPoint: .faint)).previewDisplayName("Faint")
        SubscriptionPage(viewModel: SubscriptionViewModel(presentationPoint: .gemForGold)).previewDisplayName("Gem for Gold")
        SubscriptionPage(viewModel: SubscriptionViewModel(presentationPoint: .timetravelers)).previewDisplayName("Time Travelers")
    }
}

class SubscriptionModalViewController: HostingPanModal<SubscriptionPage> {
    let viewModel: SubscriptionViewModel
    let userRepository = UserRepository()
    
    init(presentationPoint: PresentationPoint?) {
        viewModel = SubscriptionViewModel(presentationPoint: presentationPoint)
        super.init(nibName: nil, bundle: nil)
        viewModel.onSubscriptionSuccessful = {
            self.dismiss()
        }
        
        switch presentationPoint {
        case .faint:
            HabiticaAnalytics.shared.log("View death sub CTA")
        case .armoire:
            HabiticaAnalytics.shared.log("View armoire sub CTA")
        case .gemForGold:
            HabiticaAnalytics.shared.log("View gems for gold CTA")
        case .timetravelers:
            return
        case .none:
            return
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        viewModel = SubscriptionViewModel(presentationPoint: nil)
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        hostingView = UIHostingView(rootView: SubscriptionPage(viewModel: viewModel))
        super.viewDidLoad()
        view.backgroundColor = .purple400
        scrollView.backgroundColor = .purple400
        
        userRepository.getUser().on(value: {[weak self] user in
            self?.viewModel.isSubscribed = user.isSubscribed
            self?.viewModel.showHourglassPromo = user.purchased?.subscriptionPlan?.isEligableForHourglassPromo == true
        }).start()
    }
}

class SubscriptionPageController: UIHostingController<ScrollableSubscriptionPage> {
    let viewModel: SubscriptionViewModel
    let userRepository = UserRepository()
    
    init(presentationPoint: PresentationPoint?) {
        viewModel = SubscriptionViewModel(presentationPoint: presentationPoint)
        super.init(rootView: ScrollableSubscriptionPage(viewModel: viewModel))
        viewModel.onSubscriptionSuccessful = {
            self.dismiss()
        }
        
        switch presentationPoint {
        case .faint:
            HabiticaAnalytics.shared.log("View death sub CTA")
        case .armoire:
            HabiticaAnalytics.shared.log("View armoire sub CTA")
        case .gemForGold:
            HabiticaAnalytics.shared.log("View gems for gold CTA")
        case .timetravelers:
            return
        case .none:
            return
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        viewModel = SubscriptionViewModel(presentationPoint: nil)
        super.init(coder: aDecoder, rootView: ScrollableSubscriptionPage(viewModel: viewModel))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .purple300
        navigationController?.navigationBar.backgroundColor = .purple300
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.barTintColor = .purple300
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController?.navigationBar.shadowImage = UIImage()
        
        userRepository.getUser().on(value: {[weak self] user in
            self?.viewModel.isSubscribed = user.isSubscribed
            self?.viewModel.showHourglassPromo = user.purchased?.subscriptionPlan?.isEligableForHourglassPromo == true
        }).start()
    }
}

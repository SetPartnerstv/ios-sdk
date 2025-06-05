#if canImport(UIKit)
import UIKit
#endif
import WebKit
import PassKit
import SwiftProtobuf

@objc
public protocol SDKViewDelegate : NSObjectProtocol {
    func sdkViewDismiss(error: Error?)
}

private var APPSTORE_ID = "1577796889"

@objcMembers
open class SDKViewController: UIViewController, WKScriptMessageHandler, PaymentHandlerDelegate, WKNavigationDelegate, WKUIDelegate {
    
    public var token: String = ""
    public var baseUrl = "https://widget.gazprombonus.ru"
    public var queryItems: [URLQueryItem] = []
    public var httpUsername = ""
    public var httpPassword = ""
    public var applePayEnabled = false
    public weak var sdkViewDelegate: SDKViewDelegate?
    
    private var webView: WKWebView!
    private var paymentHandler: PaymentHandler!
    
    override public func loadView() {
        super.loadView()
        
        paymentHandler = PaymentHandler()
        paymentHandler.paymentDelegate = self
        
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = true

        let version = "2.1.0"
        let build = "22"

        let userScript = WKUserScript(
            source: """
                (function(){
                    window.PNWidget = window.PNWidget || {};
                    window.PNWidget._listeners = new Set();
                    window.PNWidget.version = "\(version)";
                    window.PNWidget.build = "\(build)";
                    window.PNWidget.platform = "iOS";
                    window.PNWidget.features = { auth: false, share_text: true };
                        
                    window.PNWidget.sendMobileEvent = function sendMobileEvent(event) {
                        window.webkit.messageHandlers.PNWidget.postMessage(JSON.stringify(event));
                    };
                    
                    window.PNWidget.onMobileEvent = function onMobileEvent(listener) {
                        window.PNWidget._listeners.add(listener);
                    
                        return function unsubscribe() {
                            window.PNWidget._listeners.delete(listener);
                        };
                    };

                    function wrap(fn) {
                        return function wrapper() {
                            var res = fn.apply(this, arguments);
                            window.webkit.messageHandlers.navigationStateChange.postMessage(null);
                            return res;
                        }
                    }

                    history.pushState = wrap(history.pushState);
                    history.replaceState = wrap(history.replaceState);
                    window.addEventListener('popstate', function() {
                        window.webkit.messageHandlers.navigationStateChange.postMessage(null);
                    });

                    if (window.PNWidget.onready) {
                        window.PNWidget.onready();
                    }
            
                    window.addEventListener('webViewClose', (e) => {
                        window.webkit.messageHandlers.PNWidget.postMessage('webViewClose');
                    });
                })()
            """,
            injectionTime: WKUserScriptInjectionTime.atDocumentStart,
            forMainFrameOnly: true
        )
        
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences = preferences
        webConfiguration.userContentController.add(self, name: "PNWidget")
        webConfiguration.userContentController.add(self, name: "navigationStateChange")
        webConfiguration.userContentController.addUserScript(userScript)
        webConfiguration.websiteDataStore =  WKWebsiteDataStore.default()
        
        
        webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        view.addSubview(webView)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        var urlComponents = URLComponents(string: baseUrl)!
        urlComponents.queryItems = urlComponents.queryItems ?? []
        
        if !token.isEmpty {
            urlComponents.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        
        let request = URLRequest(url: urlComponents.url!)
        
        webView.load(request)
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if (navigationAction.targetFrame == nil || !navigationAction.targetFrame!.isMainFrame) {
            webView.load(navigationAction.request)
        }

        return nil
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    @available(iOS 13.0, *)
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let pref = WKWebpagePreferences()
        if #available(iOS 14.0, *) {
            pref.allowsContentJavaScript = true
        }
        pref.preferredContentMode = .recommended

        decisionHandler(.allow, pref)
    }
    
    public func webViewWebContentProcessDidTerminate(webView: WKWebView){
        webView.reload();
    }
    
    public func webView(_ webView: WKWebView,
                        decidePolicyFor navigationResponse: WKNavigationResponse,
                        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode >= 400 && navigationResponse.isForMainFrame {
                if response.statusCode == 401, let str = response.allHeaderFields["Server"] as? String, str.caseInsensitiveCompare("QRATOR") == .orderedSame  {
                    decisionHandler(.allow)
                    return
                }
                //webView.allowsBackForwardNavigationGestures = false
                self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                handleNavigationError(error: NSError(domain: "sdk:webview", code: 1, userInfo: nil))
            }
        }
        
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error: error)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error: error)
    }
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !httpUsername.isEmpty && !httpPassword.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.proposedCredential?.user != httpUsername || challenge.proposedCredential?.password != httpPassword else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let credential = URLCredential(user: httpUsername, password: httpPassword, persistence: .none)
        completionHandler(.useCredential, credential)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        debugPrint(message.name)
        debugPrint(message.body)
        
        if (message.name == "navigationStateChange") {
            navigationStateChange();
            return;
        }
        
        if (message.body as! String == "webViewClose") {
            if let delegate = self.sdkViewDelegate {
                delegate.sdkViewDismiss(error: nil)
            }
            return;
        }
        
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        
        if let event = try?	Pbv1_MobileEvent(jsonString: message.body as! String, options: options) {
            handleEvent(event: event)
        }
    }
    
    func didAuthorizePayment(payment: PKPayment) {
        var data = Pbv1_ApplePayPaymentData()
        data.token = Pbv1_ApplePayPaymentToken()
        data.token.paymentMethod = Pbv1_ApplePaymentMethod()
        data.token.paymentData = payment.token.paymentData.base64EncodedString()
        data.token.transactionIdentifier = payment.token.transactionIdentifier
        data.token.paymentMethod.displayName = payment.token.paymentMethod.displayName ?? ""
        data.token.paymentMethod.network = payment.token.paymentMethod.network?.rawValue ?? ""
        data.token.paymentMethod.type = getPaymentMethodTypeName(type: payment.token.paymentMethod.type)
        
        var event = Pbv1_MobileEvent()
        event.type = Pbv1_MobileEventType.mobileEventApplepayPaymentDataResponse
        event.applepayPaymentData = data
        
        sendEvent(event: event)
    }
    
    public func sendEvent(event: Pbv1_MobileEvent) {
        if (webView == nil) {
            debugPrint("sendEvent: webView is null")
            return
        }
        var options = JSONEncodingOptions()
        options.preserveProtoFieldNames = true
        
        if let json = try? event.jsonString(options: options) {
            let js = """
                (function() {
                    const event = \(json);
                    for (let listener of window.PNWidget._listeners.values()) {
                        listener(event);
                    }
                })()
            """
            
            webView.evaluateJavaScript(js)
        }
        
    }
    
    open func handleEvent(event: Pbv1_MobileEvent) {
        switch event.type {
        case Pbv1_MobileEventType.mobileEventApplepayIsReadyToPayRequest:
            isReadyToPayRequest()
            break
        case Pbv1_MobileEventType.mobileEventApplepayPaymentDataRequest:
            paymentHandler.startPayment(request: event.applepayPaymentDataRequest)
            break
        case Pbv1_MobileEventType.mobileEventOpenURLRequest:
            openURL(url: event.openURLRequest)
            break
        case Pbv1_MobileEventType.mobileEventShareURLRequest:
            shareURL(url: event.shareURLRequest)
            break
        case Pbv1_MobileEventType.mobileEventReview:
            openURL(url: "itms-apps://itunes.apple.com/app/id\(APPSTORE_ID)")
            break
            
        default: break
        }
    }
    
    private func navigationStateChange() {
        if (webView.url!.relativeString.hasSuffix("/escape")) {
//            dismiss(animated: true) {}
            if let delegate = self.sdkViewDelegate {
                delegate.sdkViewDismiss(error: nil)
            }
        }
    }
    
    private func isReadyToPayRequest() {
        var event = Pbv1_MobileEvent()
        event.type = Pbv1_MobileEventType.mobileEventApplepayIsReadyToPayResponse
        event.isReadyToPay = applePayEnabled && paymentHandler.canMakePayments()
        
        sendEvent(event: event)
    }
    
    private func openURL(url: String) {
        if let link = URL(string: url.encodedURL) {
            UIApplication.shared.open(link)
        }
    }
    
    private func shareURL(url: String) {
        var items:[Any] = [Any]()
        if let link = URL(string: url) {
            items.append(link)
        }
        else {
            items.append(url)
        }
        if items.count > 0 {
            let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activityViewController.excludedActivityTypes = [.airDrop]

            present(activityViewController, animated: true)
        }
    }
    
    private func handleNavigationError(error: Error) {
        if !webView.canGoBack {
            if let delegate = self.sdkViewDelegate {
                delegate.sdkViewDismiss(error: error)
            }
        }
    }
    
    private func getPaymentMethodTypeName(type: PKPaymentMethodType) -> String {
        switch type {
        case .unknown:
            return "unknown"
        case .debit:
            return "debit"
        case .credit:
            return "credit"
        case .prepaid:
            return "prepaid"
        case .store:
            return "store"
        default:
            return "unknown"
        }
    }
}


extension String {
    var encodedURL: String {
        if self.starts(with: "http") {
            return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
        }
        return self
    }
}

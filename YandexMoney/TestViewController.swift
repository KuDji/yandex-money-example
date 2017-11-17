import UIKit
import YandexMoneySDKObjc
import WebKit

class TestViewController: UIViewController {
    
    var kSuccessUrl = "yandexmoneyapp://oauth/authorize/success"
    var kFailUrl = "yandexmoneyapp://oauth/authorize/fail"
    let kClientId = "" // Enter your Client ID
    let kHttpsScheme = "https"
    let kKeychainIdInstance = "instanceKeychainId"
    
    //Payment information
    var amount = "100"
    var payTo = "" // Enter valid Card Number
    
    var paymentRequestInfo = YMAExternalPaymentInfoModel()
    var _instanceIdQuery = [AnyHashable: Any]()
    var instanceId = String()
    var session = YMAExternalPaymentSession()
    
    @IBOutlet weak var webView: WKWebView!
    
    @IBAction func doPayment(_ sender: UIButton) {
        if kClientId == "" {
            let alert = UIAlertController(title: "Error", message: "Enter Client ID", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        } else {
            doTestPayment()
        }
    }
    
    @IBOutlet weak var myYandexClientID: UILabel!
    @IBOutlet weak var transferTo: UILabel!
    @IBOutlet weak var howMach: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.webView.navigationDelegate = self
        myYandexClientID.text = (kClientId == "" ? "Missing client ID" : kClientId)
        transferTo.text = "Transfer to: " + payTo
        howMach.text = "How mach transfer: " + amount
    }
    
    func doTestPayment() {
        // Parametr of phone transfers
        //        let paymentParams = ["amount": "100", "phone-number": "79111111111"]
        let paymentParams = ["amount": amount, "to": payTo]
        updateInstance(withCompletion: {(_ error: Error?) -> Void in
            if error != nil {
                DispatchQueue.main.async(execute: {
                    self.showError()
                })
            } else {
                // Payment request. First phase of payment is required to obtain payment info (YMAPaymentRequestInfo)
                // If you want to phone transfer change "p2p" to "phone-topup", and check parametrs
                self.startPayment(withPatternId: "p2p", andPaymentParams: paymentParams, completion: { requestInfo, paymentRequestError in
                    if paymentRequestError == nil {
                        self.paymentRequestInfo = requestInfo!
                        // Process payment request. Second phase of payment.
                        self.finishPayment()
                    } else {
                        DispatchQueue.main.async(execute: {
                            self.showError()
                        })
                    }
                })
            }
        })
    }
    
    //MARK: Payment
    func updateInstance(withCompletion block: @escaping (Error?) -> ()) {
        let currentInstanceId: String = instanceId
        if currentInstanceId.isEqual("") {
            session.instance(withClientId: kClientId, token: nil, completion: { instanceId, error in
                if error != nil {
                    block(error)
                } else {
                    self.instanceId = instanceId!
                    self.session.instanceId = instanceId
                    block(nil)
                }
            })
            return
        }
        session.instanceId = currentInstanceId
        block(nil)
    }
    
    func startPayment(withPatternId patternId: String, andPaymentParams paymentParams: [AnyHashable: Any], completion block: @escaping (_ requestInfo: YMAExternalPaymentInfoModel?, _ error: Error?) -> Void) {
        let externalPaymentRequest: YMABaseRequest? = YMAExternalPaymentRequest.externalPayment(withPatternId: patternId, paymentParameters: paymentParams)
        session.perform(externalPaymentRequest, token: nil, completion: {request, response, error in
            if error != nil {
                block(nil, error)
                return
            }
            let externalPaymentResponse = response as? YMAExternalPaymentResponse
            block(externalPaymentResponse?.paymentRequestInfo, nil)
        })
    }
    
    func finishPayment(withRequestId requestId: String, completion block: @escaping (_ asc: YMAAscModel?, _ error: Error?) -> Void) {
        
        let processExternalPaymentRequest: YMABaseRequest? = YMAProcessExternalPaymentRequest.processExternalPayment(withRequestId: requestId, successUri: kSuccessUrl, failUri: kFailUrl, requestToken: false)
        processPaymentRequest(processExternalPaymentRequest!, completion: {request, response, error -> Void in
            if error != nil {
                block(nil, error)
                return
            }
            let unknownError = NSError(domain: YMAErrorDomainUnknown,
                                       code: 0,
                                       userInfo: ["request": request as Any,
                                                  "response": response as Any])
            let processResponse = response as? YMABaseProcessResponse
            if processResponse?.status == .success {
                block(nil, nil)
            } else if processResponse?.status == .extAuthRequired {
                let processExternalPaymentResponse = response as? YMAProcessExternalPaymentResponse
                let asc: YMAAscModel? = processExternalPaymentResponse?.asc
                block(asc, unknownError)
            } else {
                block(nil, unknownError)
            }
        })
    }
    
    func processPaymentRequest(_ paymentRequest: YMABaseRequest, completion block: @escaping YMARequestHandler) {
        session.perform(paymentRequest, token: nil, completion: { request, response, error in
            let processResponse = response as? YMABaseProcessResponse
            if processResponse?.status == .inProgress {
                let popTime = DispatchTime.now() + Double((processResponse?.nextRetry)!)
                
                DispatchQueue.main.asyncAfter(deadline: popTime ,
                                              execute: {
                                                self.processPaymentRequest(request!, completion: block)
                })
            } else { block(request, response, error) }
        })
    }
    
    func finishPayment() {
        finishPayment(withRequestId: paymentRequestInfo.requestId, completion: {asc, error in
            DispatchQueue.main.async(execute: {() -> Void in
                self.processPaymentRequest(withAsc: asc)
            })
        })
    }
    
    func processPaymentRequest(withAsc asc: YMAAscModel?) {
        if asc != nil  {
            // Process info about redirect to authorization page.
            var post = ""
            
            for i in (asc?.params.enumerated())!{
                let paramKey = i.element.key
                let paramValue = i.element.value
                let temp = String(describing: paramKey) + "=" + String(describing: paramValue) + "&"
                post += temp
            }
            
            if post.count != 0 {
                if let subRange = Range<String.Index>(NSRange(location: post.count - 1, length: 1), in: post) { post.removeSubrange(subRange) }
            }
            let request = NSMutableURLRequest(url: (asc?.url)!)
            let postData: Data? = post.data(using: .utf8, allowLossyConversion: false)
            request.httpMethod = "POST"
            request.setValue("\(String(describing: postData!.count))", forHTTPHeaderField: "Content-Length")
            request.httpBody = postData
            if webView?.superview == nil {
                view.addSubview(webView ?? UIView())
            }
            webView.load(request as URLRequest)
            
        } else {
            // Success payment
            let alert = UIAlertController(title: "Success!", message: "", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
            self.webView.isHidden = true
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func addPercentEscapes(to string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    }
    
    func strippedURL(_ url: URL) -> String {
        let scheme: String? = url.scheme?.lowercased()
        let path: String? = url.path.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        let host: String? = url.host
        var port: Int? = url.port
        if port == nil {
            if scheme == kHttpsScheme {
                port = 443
            } else {
                port = 80
            }
        }
        let strippedURL: String = "\(String(describing: scheme!))://\(String(describing: host!)):\(String(describing: port!))/\(String(describing: path!))".lowercased()
        return strippedURL
    }
    
    //MARK: Keychaine
    
    func instanceID() -> String? {
        let outDictionaryRef: CFTypeRef = performQuery(instanceIdQuery())!
        if !outDictionaryRef.isEmpty {
            let outDictionary = outDictionaryRef as? [AnyHashable: Any]
            let queryResult = secItemFormat(toDictionary: outDictionary!)
            return (queryResult[kSecValueData]) as? String ?? ""
        }
        return nil
    }
    
    func setInstanceId(_ instanceId: String) {
        let outDictionaryRef: CFTypeRef = performQuery(instanceIdQuery())!
        var secItem: [AnyHashable: Any]
        if !outDictionaryRef.isEmpty {
            let outDictionary = outDictionaryRef as? [AnyHashable: Any]
            var queryResult = secItemFormat(toDictionary: outDictionary!)
            guard let kSecValueDatatext = queryResult[kSecValueData] as? String else { return }
            if kSecValueDatatext != instanceId {
                secItem = dictionary(toSecItemFormat: [kSecValueData: instanceId])
                SecItemUpdate((instanceIdQuery as! CFDictionary), (secItem as CFDictionary))
            }
            return
        }
        secItem = dictionary(toSecItemFormat: [kSecValueData: instanceId])
        secItem[kSecAttrGeneric] = kKeychainIdInstance
        SecItemAdd((secItem as CFDictionary), nil)
    }
    
    func instanceIdQuery() -> [AnyHashable: Any] {
        if _instanceIdQuery.isEmpty {
            _instanceIdQuery[kSecClass] = kSecClassGenericPassword
            _instanceIdQuery[kSecAttrGeneric] = kKeychainIdInstance
            _instanceIdQuery[kSecMatchLimit] = kSecMatchLimitOne
            _instanceIdQuery[kSecReturnAttributes] = kCFBooleanTrue
        }
        return _instanceIdQuery
    }
    
    func secItemFormat(toDictionary dictionaryToConvert: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var returnDictionary = dictionaryToConvert
        returnDictionary[kSecReturnData] = kCFBooleanTrue
        returnDictionary[kSecClass] = kSecClassGenericPassword
        let itemDataRef: CFTypeRef? = nil
        
        let data = itemDataRef as? NSData
        returnDictionary.removeValue(forKey: (kSecReturnData))
        let itemData = NSString.init(bytes: (data?.bytes)!, length: (data?.length)!, encoding: String.Encoding.utf8.rawValue)
        returnDictionary[kSecValueData] = itemData
        return returnDictionary
    }
    
    func dictionary(toSecItemFormat dictionaryToConvert: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var returnDictionary = dictionaryToConvert
        returnDictionary[kSecClass] = kSecClassGenericPassword
        let secDataString = (dictionaryToConvert[kSecValueData]) as? String
        returnDictionary[kSecValueData] = secDataString?.data(using: .utf8)
        return returnDictionary
    }
    
    func performQuery(_ query: [AnyHashable: Any]) -> CFTypeRef? {
        let outDictionaryRef: CFTypeRef? = nil
        if SecItemCopyMatching((query as CFDictionary), outDictionaryRef as? UnsafeMutablePointer<CFTypeRef?>) == errSecSuccess {
            return (outDictionaryRef ?? nil)!
        }
        return nil
    }
    
    func showError() {
        print("Error ------ в процессе выполнения программы")
        let alert = UIAlertController(title: "Error", message: "", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

extension TestViewController: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if url == nil {
            decisionHandler(.cancel)
            return
        }
        let strippedURL: String = self.strippedURL(url!)
        let strippedSuccessURL: String = self.strippedURL(URL(string: kSuccessUrl)!)
        let strippedFailURL: String = self.strippedURL(URL(string: kFailUrl)!)
        if strippedURL == strippedSuccessURL {
            let popTime = DispatchTime.now() + .seconds(2)
            DispatchQueue.main.asyncAfter(deadline: popTime, execute: {
                self.finishPayment()
            })
            webView.removeFromSuperview()
            decisionHandler(.cancel)
            return
        }
        if strippedURL == strippedFailURL {
            showError()
            webView.removeFromSuperview()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
        return
    }
}

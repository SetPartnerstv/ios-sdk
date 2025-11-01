//
//  ViewController.swift
//  GazpromBonus SDK
//
//  Created by SetPartnerstv on 12.09.2023.
//

import UIKit
import GPBonusSDK

class ViewController: UIViewController, SDKViewDelegate {

    @IBOutlet weak var versionLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        versionLabel.text = "SDK version: \(version)"
        
        let widgetButton = UIButton(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        view.addSubview(widgetButton)
        widgetButton.center = view.center
        widgetButton.backgroundColor = .systemBlue
        widgetButton.setTitle("Open Widget", for: .normal)
        widgetButton.addTarget(self, action: #selector(didTapWidgetButton), for: .touchUpInside)
        
    }

    @objc func didTapWidgetButton() {
        let sdkView = WidgetViewController()
        //TODO: place your token here
        //sdkView.token = "YOUR_TOKEN"
        sdkView.baseUrl = "https://widget.gazprombonus.ru"
        sdkView.sdkViewDelegate = self
        
        navigationController?.pushViewController(sdkView, animated: true)
    }
    
    func sdkViewDismiss(error: Error?) {
        navigationController?.popToRootViewController(animated: true)
    }
}


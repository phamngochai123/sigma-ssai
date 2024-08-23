//
//  SigmaSSAI.swift
//  SSAI Tracking
//
//  Created by Pham Hai on 07/01/2023.
//

import Foundation
import UIKit
import AVFoundation
import AVKit
import ProgrammaticAccessLibrary
import AppTrackingTransparency
import AdSupport

enum AdsEvent: String {
    case impression = "impression"
    case start = "start"
    case firstQuartile = "firstQuartile"
    case complete = "complete"
    case thirdQuartile = "thirdQuartile"
    case mute = "mute"
    case unmute = "unmute"
    case pause = "pause"
    case resume = "resume"
    case progress = "progress"
    case midpoint = "midpoint"
}

let PALTitleAlert = "Programmatic Access Nonce"
let PALTitleAlertOKAction = "OK"
let listEventCallByPlaybackTime = [AdsEvent.impression.rawValue, AdsEvent.start.rawValue, AdsEvent.firstQuartile.rawValue, AdsEvent.midpoint.rawValue, AdsEvent.complete.rawValue, AdsEvent.thirdQuartile.rawValue, AdsEvent.progress.rawValue]
let listEventCallByGesture = [AdsEvent.mute.rawValue, AdsEvent.unmute.rawValue, AdsEvent.pause.rawValue, AdsEvent.resume.rawValue]
let screenSize: CGRect = UIScreen.main.bounds

public class SigmaSSAI: NSObject, AVAssetResourceLoaderDelegate, NonceLoaderDelegate, AVPlayerItemMetadataOutputPushDelegate, AVPlayerItemLegibleOutputPushDelegate {
    //PAL
    var nonceLoader: NonceLoader!
        // The nonce manager result from the last successful nonce request.
    var nonceManager: NonceManager?
    var nonce = ""
    var videoView: UIView
    //
    var sessionUrl = ""
    var _trackingUrl = ""
    var videoUrl = ""
    var _player: AVPlayer?
    var _playerLayer: AVPlayerLayer?
    var timerTracking: Timer?
    var playbackTime = 0.0
    var adsDataFormat = [[String: Any]]()
    var adsDataGestureFormat = [[String: Any]]()
    var ssaiCallback:SigmaSSAIInterface?
    var isStartPlay = false
    var iconWta: [String: Any]? = nil
    var showingIconWta = false
    let iconImageView = UIImageView()
    let videoContainerView = UIView()
    var timeObserverToken: Any?
    var needUpdatePositionIconWta = false
    var lastSizeVideoView: CGRect
    var waittingNonce = true
    var adsRunning = false
    var lastIsMuted = false
    var lastPaused = false
    let periodicTime = 0.5
    var formateData = false
    var currentStartAdId = ""
    var countCallTracking = 0
    var showLog = false
    private var boundsObservation: NSKeyValueObservation?
    
    public init(_ sessionUrl: String, _ callback: SigmaSSAIInterface, _ videoView: UIView) {
        self.videoView = videoView
        self.lastSizeVideoView = videoView.bounds
        super.init()
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
                // Tracking authorization completed. Start loading ads here.
                self.showLog("requestTrackingAuthorization=>success")
                //PAL
                let settings = Settings()
                settings.allowStorage = true
                settings.directedForChildOrUnknownAge = false

                self.nonceLoader = NonceLoader(settings: settings)
                self.nonceLoader.delegate = self
                self.requestNonceManager()
            })
        }
        //end PAL
        self.sessionUrl = sessionUrl
        ssaiCallback = callback
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    public func setTrackingUrl(_ url: String) {
        self._trackingUrl = url
    }
    public func setShowLog(_ show: Bool) {
        self.showLog = show
    }

    // MARK: - PALNonceLoaderDelegate methods
    
    public func requestNonceManager() {
        let request = NonceRequest()
        request.continuousPlayback = .off
//        request.descriptionURL = URL(string: "https://example.com/desc?key=val")
        request.isIconsSupported = true
        request.playerType = "AVPlayer"
        request.playerVersion = "1.0.0"
//        request.ppid = "123987456"
        request.videoPlayerHeight = UInt(videoView.bounds.height)
        request.videoPlayerWidth = UInt(videoView.bounds.width)
        request.willAdAutoPlay = .on
        request.willAdPlayMuted = .off
        
        #if os(iOS)
        // OM SDK is only available on iOS.
//        request.omidPartnerName = "Gvietvn"
//        request.omidPartnerName = "6.2.1"
//        request.omidVersion = "1.2.3"
        #endif

        if let nonceManager = self.nonceManager {
            // Detach the old nonce manager's gesture recognizer before destroying it.
            self.videoView.removeGestureRecognizer(nonceManager.gestureRecognizer)
            self.nonceManager = nil
        }
        self.nonceLoader.loadNonceManager(with: request)
    }
    func presentMessage(_ message: String) {
        showLog("PAL_message=>" + message);
    }
    // Reports the start of playback for the current content session.
    func palSendPlaybackStart() {
        showLog("PAL_message=>palSendPlaybackStart");
        nonceManager?.sendPlaybackStart()
    }

    // Reports the end of playback for the current content session.
    func palSendPlaybackEnd() {
        showLog("PAL_message=>palSendPlaybackEnd");
        nonceManager?.sendPlaybackEnd()
    }

    // Reports an ad click for the current nonce manager, if not nil.
    func palSendAdClick() {
        nonceManager?.sendAdClick()
    }
    public func nonceLoader(_ nonceLoader: NonceLoader, with request: NonceRequest, didLoad nonceManager: NonceManager) {
        // Capture the created nonce manager and attach its gesture recognizer to the video view.
        self.nonceManager = nonceManager
        self.videoView.addGestureRecognizer(nonceManager.gestureRecognizer)

        showLog("Programmatic access nonce: \(nonceManager.nonce)")
        self.nonce = nonceManager.nonce
        self.presentMessage(nonceManager.nonce)
        getVideoAndTrackingUrl()
    }

    public func nonceLoader(_ nonceLoader: NonceLoader, with request: NonceRequest, didFailWith error: Error) {
        showLog("Error generating programmatic access nonce: \(error)")
        self.presentMessage(error.localizedDescription)
        self.nonce = ""
        getVideoAndTrackingUrl()
    }
    
    // MARK: getData
    public func updatePlaybackTime(playbackTime time: Double) {
        showLog("updatePlaybackTime=>ssai \(time)")
        if(videoView.bounds.width != lastSizeVideoView.width || videoView.bounds.height != lastSizeVideoView.height) {
            needUpdatePositionIconWta = true
            lastSizeVideoView = videoView.bounds
            showIconWta()
        }
        if(adsRunning) {
            let currentMuted = (self._player?.isMuted)!
            if(lastIsMuted != currentMuted) {
                lastIsMuted = currentMuted
                showLog("muteChange=>\(currentMuted)")
                callTrackingWithType(lastIsMuted ? AdsEvent.mute.rawValue : AdsEvent.unmute.rawValue)
            }
            let currentPaused = self._player?.rate == 0
            if(lastPaused != currentPaused) {
                lastPaused = currentPaused
                showLog("pauseChange=>\(currentPaused)")
                callTrackingWithType(lastPaused ? AdsEvent.pause.rawValue : AdsEvent.resume.rawValue)
            }
        }
        if(self._player?.currentTime() != nil) {
            playbackTime = CMTimeGetSeconds((self._player?.currentTime())!)
        }
    }
    
    public func metadataOutput(_: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from _: AVPlayerItemTrack?) {
        var metadata: [[String: String?]?] = []
        for metadataGroup in groups {
            for item in metadataGroup.items {
                let value = item.value as? String
                let data = Data(value!.utf8)
                do {
                    if let valueJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    {
                        let adId = valueJSON["adId"] as! String
                        let event = valueJSON["event"] as! String
                        if(event == AdsEvent.start.rawValue) {
                            currentStartAdId = adId
                            onStartPlay()
                        } else if(listEventCallByPlaybackTime.contains(event) && adId == currentStartAdId && adsRunning) {
                            if(event == AdsEvent.complete.rawValue) {
                                adsRunning = false
                                hideIconWta()
                            }
                            callTrackingWithType(event)
                        }
                    } else {
                    }
                } catch let error as NSError {
                    showLog("\(error)")
                }
                let identifier = item.identifier?.rawValue
                if let value {
                    showLog("itemMetadata=>\(value)")
                    metadata.append(["value": value, "identifier": identifier])
                }
            }
        }
    }

    public func legibleOutput(_: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers _: [Any],
                       forItemTime _: CMTime) {
    }
    public func setPlayer(_ avPlayer: AVPlayer, avPlayerLayer: AVPlayerLayer) {
        showLog("setPlayer=>ssai")
        lastPaused = false
        _player = avPlayer
        _playerLayer = avPlayerLayer
        lastIsMuted = (_player?.isMuted)!
        _player?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        listenerPlayerTime()
        // handle timedMetadata
        let metadataOutput = AVPlayerItemMetadataOutput()
        let legibleOutput = AVPlayerItemLegibleOutput()
//        metadataOutput.advanceIntervalForDelegateInvocation = NSTimeIntervalSince1970;
        _player?.currentItem?.add(metadataOutput)
        _player?.currentItem?.add(legibleOutput)
        metadataOutput.setDelegate(self, queue: .main)
        legibleOutput.setDelegate(self, queue: .main)
        legibleOutput.suppressesPlayerRendering = false
    }
    public func playerError(playerError error: Any) {
        
    }
    public func destroy() {
        
    }
    public func clear() {
        self.palSendPlaybackEnd()
        sessionUrl = ""
        _player = nil
        adsRunning = false
        adsDataFormat.removeAll()
        adsDataGestureFormat.removeAll()
        nonce = ""
        _trackingUrl = ""
        videoUrl = ""
        clearIntervalTracking()
    }
    public func setSSAILink(SSAILink link: String) {
        
    }
    func getVideoAndTrackingUrl() {
        let sessionUrlWithNonce = self.nonce.isEmpty ? sessionUrl : sessionUrl + "?play_params.nonce=" + nonce
        showLog("sessionUrlWithNonce=>\(sessionUrlWithNonce)")
        let dataSession = makeHttpRequestSync(address: sessionUrlWithNonce)
        let url = URL(string: sessionUrl)
        let sessionScheme = url?.scheme!
        let sessionDomain = url?.host!
        var sessionPort:String = ""
        if let port = url?.port {
            sessionPort = String(port)
        }
        let trackingUrl:String = dataSession["trackingUrl"] as! String
        let manifestUrl:String = dataSession["manifestUrl"] as! String
        let isFullPath = manifestUrl.hasPrefix("http")
        let isAbsolutePath = manifestUrl.hasPrefix("/")
        let isRelativePath = manifestUrl.hasPrefix(".")
        let baseURL = sessionScheme! + "://" + sessionDomain! + (!sessionPort.isEmpty ? ":" + sessionPort : "")
        if(isFullPath) {
            videoUrl = manifestUrl
            self._trackingUrl = trackingUrl
        }
        if(isAbsolutePath) {
            videoUrl = baseURL + manifestUrl
            self._trackingUrl = baseURL + trackingUrl
        }
        if(isRelativePath) {
            videoUrl = URL(string: manifestUrl, relativeTo: URL(string: sessionUrl))!.absoluteString
            self._trackingUrl = URL(string: trackingUrl, relativeTo: URL(string: sessionUrl))!.absoluteString
        }
        ssaiCallback?.onSessionInitSuccess(videoUrl)
    }
    public func onStartPlay() {
        adsRunning = true
        adsDataGestureFormat.removeAll()
        if(countCallTracking >= 5 || adsDataFormat.indices.count >= 50) {
            adsDataFormat.removeAll()
            countCallTracking = 0
        }
        makeHttpRequestSessionSync(address: _trackingUrl)
    }
    func clearIntervalTracking() {
        timerTracking?.invalidate()
    }
    func formatDataTracking(data: [String: Any]){
        if(data.count > 0) {
            countCallTracking += 1
            var hasFirstEventStart = false
            var hasFirstEventImpression = false
            let groupsAds = data["avails"] as! [[String: Any]]
            var findedListAds = false
            for itemGroup in groupsAds {
                if(findedListAds) {
                    break
                }
                let idGroup = String(itemGroup["id"] as! Int)
                let ads = itemGroup["ads"] as! [[String: Any]]
                var hasIconWta = false
                for itemAds in ads {
                    let idAds = itemAds["id"] as! String
                    if(idAds == currentStartAdId) {
                        let icons = itemAds["icons"] as! [[String: Any]]
                        for icon in icons {
                            if((icon["program"] as! String) == "GoogleWhyThisAd" && !hasIconWta) {
                                let staticResource = icon["staticResource"] as! [String: Any]
                                let uri = staticResource["uri"] as! String
                                if(uri.count > 0) {
                                    hasIconWta = true
                                    iconWta = icon
                                }
                            }
                        }
                        showLog("hasIconWta=>\(hasIconWta)")
                        let trackingEvents = itemAds["trackingEvents"] as! [[String: Any]]
                        for trackEvent in trackingEvents {
                            let eventType = trackEvent["eventType"] as! String
                            let beaconUrls = trackEvent["beaconUrls"] as! [String]
                            var firstUrlTracking = ""
                            if(beaconUrls.count > 0) {
                                firstUrlTracking = beaconUrls[0]
                            }
                            let startTimeInSeconds = trackEvent["startTimeInSeconds"] as! Double
                            var itemTrackFormat:Dictionary = [String: Any]()
                            let idItemTrack = idGroup + idAds + eventType + String(startTimeInSeconds)
                            let itemTrackFind = adsDataFormat.filter({($0["id"] as! String) == idItemTrack})
                            if(itemTrackFind.count <= 0) {
                                if(eventType == AdsEvent.start.rawValue || eventType == AdsEvent.impression.rawValue) {
                                    findedListAds = true
                                    if(!hasFirstEventStart || !hasFirstEventImpression) {
                                        if(eventType == AdsEvent.start.rawValue) {
                                            hasFirstEventStart = true
                                        }
                                        if(eventType == AdsEvent.impression.rawValue) {
                                            hasFirstEventImpression = true
                                        }
                                        if(firstUrlTracking.starts(with: "http")) {
                                            showLog("callTrackingWithType=>\(eventType) \(firstUrlTracking)")
                                            makeHttpRequest(firstUrlTracking)
                                        }
                                        if(hasIconWta && !showingIconWta) {
                                            showIconWta()
                                        }
                                        itemTrackFormat["isCalled"] = true
                                    } else {
                                        itemTrackFormat["isCalled"] = false
                                    }
                                } else {
                                    itemTrackFormat["isCalled"] = false
                                }
                                itemTrackFormat["id"] = idItemTrack
                                itemTrackFormat["adId"] = idAds
                                itemTrackFormat["eventType"] = eventType
                                itemTrackFormat["startTimeInSeconds"] = startTimeInSeconds
                                itemTrackFormat["url"] = firstUrlTracking
                                itemTrackFormat["beaconUrls"] = beaconUrls
                                if(listEventCallByPlaybackTime.contains(eventType)) {
                                    adsDataFormat.append(itemTrackFormat)
                                } else if(listEventCallByGesture.contains(eventType)) {
                                    adsDataGestureFormat.append(itemTrackFormat)
                                }
                            }
                            showLog("firstUrlTracking=>\(firstUrlTracking)")
                        }
                    }
                }
                if(!hasIconWta) {
                    iconWta = nil
                }
            }
        }
    }
    // Method to check if the player is playing or paused
    func checkPlayerState() -> Bool {
        return self._player?.rate != 0
    }
    func checkAdsPlaying() -> Bool {
        return adsRunning
    }
    @objc private func appDidBecomeActive(_ gesture: UITapGestureRecognizer) {
        self._player?.play()
    }
    @objc private func appDidEnterBackground(_ gesture: UITapGestureRecognizer) {
        self._player?.pause()
    }
    func openUrl(_ url: String) {
        guard let url = URL(string: url) else {
          return //be safe
        }
        if #available(iOS 10.0, *) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            UIApplication.shared.openURL(url)
        }
    }
    @objc private func handleIconWtaTapped(_ gesture: UITapGestureRecognizer) {
        if gesture.view is UIImageView {
          showLog("handleIconWtaTapped=>")
           let iconClickThrough = iconWta!["iconClickThrough"] as! [String: String]
           let url = iconClickThrough["data"]!
           if(!url.isEmpty) {
               openUrl(url)
           }
       }
    }
    func showIconWta() {
        if(iconWta != nil && (!showingIconWta || (showingIconWta && needUpdatePositionIconWta))) {
            if(needUpdatePositionIconWta) {
//                hideIconWta()
            }
            let height = iconWta!["height"] as! Double
            let width = iconWta!["width"] as! Double
            let xPosition = iconWta!["xPosition"] as! String
            let yPosition = iconWta!["yPosition"] as! String
            if(height == 0.0 || width == 0.0) {
                hideIconWta()
            } else {
                var xPositionNumber = 0.0
                var yPositionNumber = 0.0
                if(xPosition == "left") {
                    xPositionNumber = videoView.safeAreaInsets.left
                } else if(xPosition == "right") {
                    xPositionNumber = videoView.bounds.width - width - videoView.safeAreaInsets.right
                } else {
                    xPositionNumber = Double(xPosition)!
                }
                if(yPosition == "top") {
                    yPositionNumber = videoView.safeAreaInsets.top
                } else if(yPosition == "bottom") {
                    yPositionNumber = videoView.bounds.height - height - videoView.safeAreaInsets.bottom
                } else {
                    yPositionNumber = Double(yPosition)!
                }
                showLog("positionWta=>\(width) \(height) \(xPositionNumber) \(yPositionNumber) \(screenSize.width) \(screenSize.height) \(self.videoView.safeAreaInsets)")
                showingIconWta = true
                if(needUpdatePositionIconWta) {
                    iconImageView.frame.origin = CGPoint(x: xPositionNumber, y: yPositionNumber)
                    videoView.layoutIfNeeded()
                } else {
                    let staticResource = iconWta!["staticResource"] as! Dictionary<String, String>
                    if let iconUri: String = staticResource["uri"] {
                        showLog("iconUri=>\(iconUri)")
                        iconImageView.isUserInteractionEnabled = true
                        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleIconWtaTapped))
                        iconImageView.addGestureRecognizer(tapGesture)
                        iconImageView.translatesAutoresizingMaskIntoConstraints = false
                        self.videoView.addSubview(iconImageView)
                        NSLayoutConstraint.activate([
                            iconImageView.topAnchor.constraint(equalTo: videoView.topAnchor, constant: yPositionNumber),
                            iconImageView.leftAnchor.constraint(equalTo: videoView.leftAnchor, constant: xPositionNumber),
                            iconImageView.widthAnchor.constraint(equalToConstant: width),
                            iconImageView.heightAnchor.constraint(equalToConstant: height)
                        ])
                        if let iconURL = URL(string: iconUri) {
                            let task = URLSession.shared.dataTask(with: iconURL) { data, response, error in
                                guard let data = data, error == nil else {
                                    self.showLog("Failed to download image: \(error?.localizedDescription ?? "No error description")")
                                    return
                                }
                                DispatchQueue.main.async {
                                    self.iconImageView.image = UIImage(data: data)
                                }
                            }
                            task.resume()
                        }
                    }
                }
            }

        }
    }
    func hideIconWta() {
        if(showingIconWta) {
            showLog("hideIconWta=>")
            showingIconWta = false
            self.iconImageView.removeFromSuperview()
            self.videoContainerView.removeFromSuperview()
        }
    }
    func callTrackingWithType(_ type: String) {
        let isEventTime = listEventCallByPlaybackTime.contains(type)
        let isEventGesture = listEventCallByGesture.contains(type)
        var dataCheck = isEventTime ? adsDataFormat : adsDataGestureFormat
        for row in dataCheck.indices {
            let itemAdsDataFormat = dataCheck[row]
            let eventType = itemAdsDataFormat["eventType"] as! String
            let isCalled = itemAdsDataFormat["isCalled"] as! Bool
            if(isCalled) {
                continue
            }
            let url = itemAdsDataFormat["url"] as! String
            if(eventType == type) {
                if(url.starts(with: "http")) {
                    let startTimeInSeconds = itemAdsDataFormat["startTimeInSeconds"] as! Double
                    showLog("callTrackingWithType=>\(type), \(startTimeInSeconds), \(playbackTime)")
                    makeHttpRequest(url)
                }
                   dataCheck[row]["isCalled"] = true
            }
            if(isEventTime) {
                adsDataFormat = dataCheck
            } else if(isEventGesture) {
                adsDataGestureFormat = dataCheck
            }
        }
    }
    @objc func eventWith(timer: Timer!) {
        makeHttpRequestSessionSync(address: _trackingUrl)
    }
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let player = object as? AVPlayer, player == _player, keyPath == "status" {
            if player.status == .readyToPlay {
                self.palSendPlaybackStart()
            } else if player.status == .failed {
                showLog("VideoError=>\(String(describing: player.error))")
            }
        }
    }
    func listenerPlayerTime() {
        _player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: periodicTime, preferredTimescale: 2), queue: DispatchQueue.main) { [weak self] (sec) in
            let seconds = CMTimeGetSeconds(sec)
            self!.updatePlaybackTime(playbackTime: seconds)
        }
    }
    func makeHttpRequest(_ url: String) {
        showLog("callTrackingUrl=>\(url)")
        let url = URL(string: url)!
        let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
            guard data != nil else { return }
        }
        task.resume()
    }
    func makeHttpRequestSync(address: String) -> Dictionary<String, Any> {
        let url = URL(string: address)
        let semaphore = DispatchSemaphore(value: 0)
        
        var result: String = ""
        var dataReturn: Dictionary = [String: Any]()
        
        let task = URLSession.shared.dataTask(with: url!) { [self](data, response, error) in
            result = String(data: data!, encoding: String.Encoding.utf8)!
            dataReturn = convertToDictionary(text: result)!
            semaphore.signal()
        }
        
        task.resume()
        semaphore.wait()
        return dataReturn
    }
    func makeHttpRequestSessionSync(address: String) {
        let url = URL(string: address)
        let semaphore = DispatchSemaphore(value: 0)
        
        var result: String = ""
        var dataReturn: Dictionary = [String: Any]()
        let task = URLSession.shared.dataTask(with: url!) { [self](data, response, error) in
            if(data != nil) {
                result = String(data: data!, encoding: String.Encoding.utf8)!
                if result.contains("avails") {
                    dataReturn = convertToDictionary(text: result)!
                } else {
                    ssaiCallback?.onSessionFail()
                }
            } else {
                ssaiCallback?.onSessionFail()
            }
            semaphore.signal()
        }
        
        task.resume()
        semaphore.wait()
        formatDataTracking(data: dataReturn)
    }
    func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
    public func showLog(_ message: String) {
        if(showLog) {
            print("SSAI_LOG: \(message)")
        }
    }
}

//
//  ViewController.swift
//  FaceDetection
//

import UIKit
import CoreImage
import AVFoundation
import Foundation


protocol VideoFeedDelegate {
    func videoFeed(_ videoFeed: VideoFeed, didUpdateWithSampleBuffer sampleBuffer: CMSampleBuffer!)
}


var title:String = "Memr"
var buffer = 0
var video_state = 0
var mirror_state = 0
var frame_counter = 0
var camera_position = "front"

var topMeme: String = ""
var bottomMeme: String = ""

class VideoFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
    let outputQueue = DispatchQueue(label: "VideoDataOutputQueue", attributes: [])
    
    var device: AVCaptureDevice?
    
        
    func getDevice() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as! [AVCaptureDevice]
        var camera: AVCaptureDevice? = nil
        for device in devices {
            if camera_position == "front" && device.position == .front {
                camera = device
            }
            else if device.position == .back {
                camera = device
            }
        }
        return camera
    }
    
    var input: AVCaptureDeviceInput? = nil
    var delegate: VideoFeedDelegate? = nil
    var session: AVCaptureSession! = nil
    
    let videoDataOutput: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as AnyHashable: NSNumber(value: kCMPixelFormat_32BGRA as UInt32) ]
        output.alwaysDiscardsLateVideoFrames = true
        return output
    }()
    
    func start() throws {
        device = getDevice()
        session = {
            let session = AVCaptureSession()
            session.sessionPreset = AVCaptureSessionPreset1280x720
            return session
        }()
        var error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
        do {
            try configure()
            session.startRunning()
            return
        } catch let error1 as NSError {
            error = error1
        }
        throw error
    }
    
    func stop() {
        session.stopRunning()
    }
    
    fileprivate func configure() throws {
        var error: NSError! = NSError(domain: "Migrator", code: 0, userInfo: nil)
        do {
            let maybeInput: AnyObject = try AVCaptureDeviceInput(device: device!)
            input = maybeInput as? AVCaptureDeviceInput
            if session.canAddInput(input) {
                session.addInput(input)
                videoDataOutput.setSampleBufferDelegate(self, queue: outputQueue);
                if session.canAddOutput(videoDataOutput) {
                    session.addOutput(videoDataOutput)
                    let connection = videoDataOutput.connection(withMediaType: AVMediaTypeVideo)
                    connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                    return
                } else {
                    print("Video output error.");
                }
            } else {
                print("Video input error. Maybe unauthorised or no camera.")
            }
        } catch let error1 as NSError {
            error = error1
            print("Failed to start capturing video with error: \(error)")
        }
        throw error
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // Update the delegate
        if delegate != nil {
            delegate!.videoFeed(self, didUpdateWithSampleBuffer: sampleBuffer)
        }
    }
}

class FaceObscurationFilter {
    let inputImage: CIImage
    var outputImage: CIImage? = nil
    var originX: CGFloat? = nil
    var originY: CGFloat? = nil
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var radius: CGFloat? = nil
    
    var bounder: UIView!
    var emotion: String
    
//    fileprivate lazy var client : ClarifaiClient = ClarifaiClient(appID: clarifaiClientID, appSecret: clarifaiClientSecret)
    
    var delegate: ViewControllerDelegate?
    
    init(inputImage: CIImage) {
        self.inputImage = inputImage
        self.emotion = "None"
        recognizeImage(UIImage(ciImage: inputImage))
    }
    
    convenience init(sampleBuffer: CMSampleBuffer, delegate: ViewControllerDelegate?) {
        // Create a CIImage from the buffer
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let image = CIImage(cvPixelBuffer: imageBuffer!)
        
        self.init(inputImage: image)
        
        self.delegate = delegate
    }
    
    func process() {
        // Detect any faces in the image
        let detector = CIDetector(ofType: CIDetectorTypeFace, context:nil, options:nil)
        var featureArgs = [String: AnyObject]()
        featureArgs[CIDetectorSmile] = true as AnyObject?
        let features = detector?.features(in: inputImage,options: featureArgs)
    
        
        // Build a masking image for each of the faces
        let maskImage: CIImage? = nil
        
        frame_counter += 1
        
        if frame_counter == 1 {
            if features?.count == 0 {
                delegate?.updateRectangleFrame(CGRect.zero, emotion: emotion)
            }
            else {
                for feature in features! {
                    if (feature.type == CIFeatureTypeFace) {
                        let frame = CGRect(x: feature.bounds.origin.x, y: feature.bounds.origin.y, width: feature.bounds.size.width, height: feature.bounds.size.height)
                        if ((feature as! CIFaceFeature).hasSmile) {
                            emotion = "happy"
                            buffer = 8
                        }
                        delegate?.updateRectangleFrame(frame, emotion: emotion)
                        
                    }
                }
            }
            frame_counter = 0
        }
        
        // Create a single blended image made up of the pixellated image, the mask image, and the original image.
        // We want sections of the pixellated image to be removed according to the mask image, to reveal
        // the original image in the background.
        // We use the CIBlendWithMask filter for this, and set the background image as the original image,
        // the input image (the one to be masked) as the pixellated image, and the mask image as, well, the mask.
        var blendOptions = [String: AnyObject]()
        //blendOptions[kCIInputImageKey] = pixellatedImage
        blendOptions[kCIInputBackgroundImageKey] = inputImage
        blendOptions[kCIInputMaskImageKey] = maskImage
        let blend = CIFilter(name: "CIBlendWithMask", withInputParameters: blendOptions)
        
        // Finally, set the resulting image as the output
        outputImage = blend!.outputImage
    }
    
    
    fileprivate func recognizeImage(_ image: UIImage!) {
        // Scale down the image. This step is optional. However, sending large images over the
        // network is slow and does not significantly improve recognition performance.
        let size = CGSize(width: 320, height: 320 * image.size.height / image.size.width)
        UIGraphicsBeginImageContext(size)
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Encode as a JPEG.
        _ = UIImageJPEGRepresentation(scaledImage!, 0.9)!
        
        // Send the JPEG to Clarifai for standard image tagging.
//        client.recognizeJpegs([jpeg]) {
//            (results: [ClarifaiResult]?, error: NSError?) in
//            if error != nil {
//                //print("Error: \(error)\n")
//            } else {
//                for result in results! {
//                    if (result == "joy"  || result == "happiness" || result == "smile" || result == "facial expression") {
        self.emotion = "happy"
//                        break
//                    }
//                }
//            }
//        }
    }
}

class ViewController: UIViewController, VideoFeedDelegate, ViewControllerDelegate {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var changeCameraButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var refreshButton: UIButton!
    
    var feed: VideoFeed = VideoFeed()
    
    var topText = UILabel()
    var bottomText = UILabel()
    var currSpeed = 0.0
    var rectPrevX = -1.0
    var rectPrevY = -1.0
    
    override func awakeFromNib() {
        super.awakeFromNib()
        getText();
        feed.delegate = self
        view.insertSubview(topText, at: 1)
        view.insertSubview(bottomText, at: 1)
        
        topText.textAlignment = NSTextAlignment.center;
        topText.numberOfLines = 0
        topText.adjustsFontSizeToFitWidth = true
        topText.minimumScaleFactor = 0.5
        
        bottomText.textAlignment = NSTextAlignment.center;
        bottomText.numberOfLines = 0
        bottomText.adjustsFontSizeToFitWidth = true
        bottomText.minimumScaleFactor = 0.5
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(refresh(_:)))
        refreshButton.addGestureRecognizer(gestureRecognizer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startVideoFeed()
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        feed.stop()
        
    }
    
    override func viewDidLoad() {
        
    }

    func refresh(_ sender: UITapGestureRecognizer) {
        getText();
    }
    
    func startVideoFeed() {
        do {
            try feed.start()
            print("Video started.")
            
        }
        catch {
            // alert?
            // need to look into device permissions
        }
        
    }
    
    func videoFeed(_ videoFeed: VideoFeed, didUpdateWithSampleBuffer sampleBuffer: CMSampleBuffer!) {
        if video_state == 0 {
            let filter = FaceObscurationFilter(sampleBuffer: sampleBuffer, delegate: self)
            filter.process()
            DispatchQueue.main.async(execute: { () -> Void in
                let img : CGImage = self.convertCIImageToCGImage(inputImage : filter.outputImage!)
                if mirror_state == 0 {
                    self.imageView.image = UIImage(cgImage: img, scale: 1.0, orientation: .upMirrored)
                }
                else {
                    self.imageView.image = UIImage(cgImage : img)
                }
            })
        }
    }
    
    func updateRectangleFrame(_ rect: CGRect, emotion: String) {
        DispatchQueue.main.async {
            let partOne = pow((Double(rect.origin.x) - Double(self.rectPrevX)), 2.0)
            let partTwo = pow((Double(rect.origin.y) - Double(self.rectPrevY)), 2.0)
            self.currSpeed = (sqrt(partOne + partTwo))
            if self.currSpeed >= 20.0 {
                let fontSize = 10000.0/rect.width
                
                let topRect : CGRect = CGRect(x: -(rect.origin.x-rect.width/1.5), y: -(rect.origin.y-rect.height/0.8), width: rect.width, height: rect.height)
                let bottomRect : CGRect = CGRect(x: -(rect.origin.x-rect.width/1.5), y: -(rect.origin.y-rect.height/0.4), width: rect.width, height: rect.height)
                /*let topRect : CGRect = CGRect(x: -(0.0), y: -(0.0), width: rect.width, height: rect.height/2)
                 let bottomRect : CGRect = CGRect(x: -(0.0), y: -(0.0), width: rect.width, height: rect.height/2)*/
 
                self.rectPrevX = Double(rect.origin.x)
                self.rectPrevY = Double(rect.origin.y)
                
                self.topText.frame = topRect
                self.bottomText.frame = bottomRect
                
                if emotion == "happy" || buffer > 0 {
                    
                    self.topText.font =  UIFont(name: "impact", size: fontSize)
                    self.topText.attributedText = NSMutableAttributedString(string: topMeme, attributes: [NSFontAttributeName : self.topText.font,NSForegroundColorAttributeName: UIColor.white, NSStrokeColorAttributeName: UIColor.black, NSStrokeWidthAttributeName: -3])
                    
                    self.bottomText.font =  UIFont(name: "impact", size: fontSize)
                    self.bottomText.attributedText = NSMutableAttributedString(string: bottomMeme, attributes: [NSFontAttributeName : self.bottomText.font,NSForegroundColorAttributeName: UIColor.white, NSStrokeColorAttributeName: UIColor.black, NSStrokeWidthAttributeName: -3])
                    buffer -= 1
                }
            }
            
            if self.rectPrevX == -1.0 {
                self.rectPrevX = Double(rect.origin.x)
                self.rectPrevY = Double(rect.origin.y)
            }
         }
    }
    
    @IBAction func cameraButtonPressed(_ sender: UIButton) {
        
        sender.isHidden = true
        changeCameraButton.isHidden = true
        refreshButton.isHidden = true
        
        AudioServicesPlaySystemSound(1108)
        
        screenshot()
        
        sender.isHidden = false
        changeCameraButton.isHidden = false
        refreshButton.isHidden = false
        
        UIView.animate(withDuration: 0.5, animations: {
            self.imageView.alpha = 0.7
            }, completion: {
                (value: Bool) in
                self.imageView.alpha = 1.0
        })
        
        video_state = 1
        let seconds = 1
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(seconds) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC)) {
            video_state = 0
        }
    }
    
    func screenshot() {
        UIGraphicsBeginImageContext(view.frame.size)
        view.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        UIImageWriteToSavedPhotosAlbum(image!, nil, nil, nil)
    }
    
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage! {
        let context = CIContext(options: nil)
        if context != nil {
            return context.createCGImage(inputImage, from: inputImage.extent)
        }
        return nil
    }
    
    func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {
            let ac = UIAlertController(title: "Saved!", message: "You have been memified!", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        }
    }
    
    @IBAction func cameraChange(_ sender: UIButton) {
        if camera_position == "front" {
            camera_position = "back"
            mirror_state = 1;
        }
        else{
            camera_position = "front"
            mirror_state = 0;
        }
        do{
            try feed.start();
        }
        catch{}
    }
    
    func getDocumentsDirectory() -> NSString {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        return documentsDirectory as NSString
    }
    
    
    
    func HTTPsendRequest(request: NSMutableURLRequest,callback: @escaping (String, String?) -> Void) {
        
        let task = URLSession.shared.dataTask(with: request as URLRequest,completionHandler :
            {
                data, response, error in
                if error != nil {
                    callback("", (error!.localizedDescription) as String)
                } else {
                    callback(NSString(data: data!, encoding: String.Encoding.utf8.rawValue) as! String,nil)
                }
        })
        
        task.resume() //Tasks are called with .resume()
        
    }
    // If you found this, Harambe will bless you.
    func HTTPGet(url: String, callback: @escaping (String, String?) -> Void) {
        let request = NSMutableURLRequest(url: NSURL(string: url)! as URL) //To get the URL of the receiver , var URL: NSURL? is used
        HTTPsendRequest(request: request, callback: callback)
    }
    
    func getText() {
        let memes = [
            (top: "How you look when", bottom: "When you're supposed to be studying for finals"),
            (top: "How you look when you wake up", bottom: "And the charger wasn't plugged in"),
            (top: "When you finally realize your winter body", bottom: "When you tell everyone about your summer body goals"),
            (top: "When you're on a diet", bottom: "and people keep bringing junk food to work"),
            (top: "I didn't choose the thug life", bottom: "The thug life chose me"),
            (top: "When people say", bottom: "Harambe was just a gorilla"),
            (top: "You thought your meme was so edgy", bottom: "But then it got removed"),
            (top: "When someone gets up to hand in their final", bottom: "and you haven't started")
        ]
        let num = Int(arc4random_uniform(8))
        topMeme = memes[num].top.uppercased()
        bottomMeme = memes[num].bottom.uppercased()
    }
}

protocol ViewControllerDelegate {
    func updateRectangleFrame(_ rect: CGRect, emotion: String)
}

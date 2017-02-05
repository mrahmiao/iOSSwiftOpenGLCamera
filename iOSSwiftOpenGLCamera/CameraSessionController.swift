//
//  CameraSessionController.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import CoreImage

@objc protocol CameraSessionControllerDelegate {
	@objc optional func cameraSessionDidOutputSampleBuffer(_ sampleBuffer: CMSampleBuffer!)
}

class CameraSessionController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	
	var session: AVCaptureSession!
	var sessionQueue: DispatchQueue!
	var videoDeviceInput: AVCaptureDeviceInput!
	var videoDeviceOutput: AVCaptureVideoDataOutput!
	var stillImageOutput: AVCaptureStillImageOutput!
	var runtimeErrorHandlingObserver: Any!
	
	var sessionDelegate: CameraSessionControllerDelegate?
	
	
	/* Class Methods
	------------------------------------------*/
	
	class func deviceWithMediaType(mediaType: String, position: AVCaptureDevicePosition) -> AVCaptureDevice? {

    guard let devices = AVCaptureDevice.devices(withMediaType: mediaType) as? [AVCaptureDevice] else {
      return nil
    }

    for device in devices where device.position == position {
      return device
    }

    return nil

	}
	
	
	/* Lifecycle
	------------------------------------------*/
	
	override init() {
		super.init();
		
		session = AVCaptureSession()
		
		session.sessionPreset = AVCaptureSessionPresetMedium;
		
		authorizeCamera();

    sessionQueue = DispatchQueue(label: "CameraSessionController Session")

    sessionQueue.async { [unowned self] in
      self.session.beginConfiguration()
      self.addVideoInput()
      self.addVideoOutput()
      self.addStillImageOutput()
      self.session.commitConfiguration()
    }

	}
	
	
	/* Instance Methods
	------------------------------------------*/
	
	func authorizeCamera() {
		AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { isGranted in
			// If permission hasn't been granted, notify the user.
			if !isGranted {
        DispatchQueue.main.async {
          UIAlertView(
            title: "Could not use camera!",
            message: "This application does not have permission to use camera. Please update your privacy settings.",
            delegate: self,
            cancelButtonTitle: "OK").show()
        }
      }
    }
	}
	
	func addVideoInput() {
		
    guard let videoDevice: AVCaptureDevice = CameraSessionController.deviceWithMediaType(mediaType: AVMediaTypeVideo, position: .back) else {
      fatalError("No camera")
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: videoDevice)
    } catch {
      fatalError("No device input")
    }

    if session.canAddInput(input) {
      session.addInput(input)
    }
	}
	
	func addVideoOutput() {
		
		videoDeviceOutput = AVCaptureVideoDataOutput()
		
		videoDeviceOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

		videoDeviceOutput.alwaysDiscardsLateVideoFrames = true
		videoDeviceOutput.setSampleBufferDelegate(self, queue: sessionQueue)
		
		if session.canAddOutput(videoDeviceOutput) {
			session.addOutput(videoDeviceOutput)
		}
	}
	
	func addStillImageOutput() {
		stillImageOutput = AVCaptureStillImageOutput()
		stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
		
		if session.canAddOutput(stillImageOutput) {
			session.addOutput(stillImageOutput)
		}
	}
	
	func startCamera() {
    sessionQueue.async { [weak self] in

      guard let strongSelf = self else {
        return
      }

      strongSelf.runtimeErrorHandlingObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: strongSelf.sessionQueue, queue: nil) { (note: Notification) in

        strongSelf.sessionQueue.async {
          strongSelf.session.startRunning()
        }

      }

			self?.session.startRunning()
		}
	}
	
	func teardownCamera() {
    sessionQueue.async { [weak self] in
      guard let strongSelf = self else {
        return
      }

      strongSelf.session.stopRunning()
      NotificationCenter.default.removeObserver(strongSelf.runtimeErrorHandlingObserver)
    }
	}
	
	func focusAndExposeAtPoint(point: CGPoint) {
    sessionQueue.async { [unowned self] in
      guard let device = self.videoDeviceInput.device else {
        fatalError(#function)
      }

      do {
        try device.lockForConfiguration()
      } catch {
        fatalError(String(describing: error))
      }

      defer {
        device.unlockForConfiguration()
      }

      if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
      }

      if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
      }
    }
  }

  func captureImage(completion: ((UIImage?, Error?) -> Void)? = nil) {

    sessionQueue.async { [unowned self] in

      let connection = self.stillImageOutput.connection(withMediaType: AVMediaTypeVideo)

      self.stillImageOutput.captureStillImageAsynchronously(from: connection) { buffer, error in

        guard error == nil else {
          completion?(nil, nil)
          return
        }

        guard let buffer = buffer, let jpegData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer), let image = UIImage(data: jpegData) else {
          completion?(nil, nil)
          return
        }

        completion?(image, nil)
      }
    }
  }

	
	/* AVCaptureVideoDataOutput Delegate
	------------------------------------------*/
	
	func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
		if (connection.isVideoOrientationSupported){
			//connection.videoOrientation = .portraitUpsideDown
			connection.videoOrientation = .portrait
		}
		if (connection.isVideoMirroringSupported) {
			//connection.videoMirrored = true
			connection.isVideoMirrored = false
		}
		sessionDelegate?.cameraSessionDidOutputSampleBuffer?(sampleBuffer)
	}
	
}

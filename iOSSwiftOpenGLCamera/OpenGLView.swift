//
//  OpenGLView.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import Foundation
import UIKit
import QuartzCore
import OpenGLES
import GLKit
import CoreMedia
import AVFoundation


struct Vertex {
	var Position: (CFloat, CFloat, CFloat)
	var TexCoord: (CFloat, CFloat)
}

var Vertices: (Vertex, Vertex, Vertex, Vertex) = (
	Vertex(Position: (1, -1, 0) , TexCoord: (1, 1)),
	Vertex(Position: (1, 1, 0)  , TexCoord: (1, 0)),
	Vertex(Position: (-1, 1, 0) , TexCoord: (0, 0)),
	Vertex(Position: (-1, -1, 0), TexCoord: (0, 1))
)

var Indices: (GLubyte, GLubyte, GLubyte, GLubyte, GLubyte, GLubyte) = (
	0, 1, 2,
	2, 3, 0
)


class OpenGLView: UIView {
	
	var eaglLayer: CAEAGLLayer!
	var context: EAGLContext!
	var colorRenderBuffer: GLuint = GLuint()
	var positionSlot: GLuint = GLuint()
	var texCoordSlot: GLuint = GLuint()
	var textureUniform: GLuint = GLuint()
	var timeUniform: GLuint = GLuint()
	var showShaderBoolUniform: GLuint = GLuint()
	var indexBuffer: GLuint = GLuint()
	var vertexBuffer: GLuint = GLuint()
	var videoTexture: CVOpenGLESTexture?
	var videoTextureID: GLuint?
	var coreVideoTextureCache: CVOpenGLESTextureCache?
	
	var textureWidth: Int = 0
	var textureHeight: Int = 0
	
	var time: GLfloat = 0.0
	var showShader: GLfloat = 1.0
	
	var frameTimestamp: Double = 0.0
	
	/* Class Methods
	------------------------------------------*/

  override class var layerClass: AnyClass {
		// In order for our view to display OpenGL content, we need to set it's
		//   default layer to be a CAEAGLayer
		return CAEAGLLayer.self
	}
	
	
	/* Lifecycle
	------------------------------------------*/

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		
		setupLayer()
		setupContext()
		setupRenderBuffer()
		setupFrameBuffer()
		compileShaders()
		setupVBOs()
		setupDisplayLink()
		
		self.contentScaleFactor =  UIScreen.main.scale
	}

	
	/* Setup Methods
	------------------------------------------*/
	
	func setupLayer() {
		// CALayer's are, by default, non-opaque, which is 'bad for performance with OpenGL',
		//   so let's set our CAEAGLLayer layer to be opaque.
		eaglLayer = layer as! CAEAGLLayer
		eaglLayer.isOpaque = true

	}
	
	func setupContext() {
		// Just like with CoreGraphics, in order to do much with OpenGL, we need a context.
		//   Here we create a new context with the version of the rendering API we want and
		//   tells OpenGL that when we draw, we want to do so within this context.
    guard let context = EAGLContext(api: .openGLES2) else {
      fatalError("Failed to initialize OpenGLES 2.0 context!")
    }

    self.context = context
		
		if (!EAGLContext.setCurrent(context)) {
			fatalError("Failed to set current OpenGL context!")
		}

		let err: CVReturn = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &coreVideoTextureCache)

    guard err == kCVReturnSuccess else {
      fatalError("Failed to create texture cache.")
    }
	}

	func setupRenderBuffer() {
		// A render buffer is an OpenGL object that stores the rendered image to present to the screen.
		//   OpenGL will create a unique identifier for a render buffer and store it in a GLuint.
		//   So we call the glGenRenderbuffers function and pass it a reference to our colorRenderBuffer.
		glGenRenderbuffers(1, &colorRenderBuffer)
		// Then we tell OpenGL that whenever we refer to GL_RENDERBUFFER, it should treat that as our colorRenderBuffer.
		glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
		// Finally, we tell our context that the render buffer for our layer is our colorRenderBuffer.
		_ = context.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer)
	}
	
	func setupFrameBuffer() {
		// A frame buffer is an OpenGL object for storage of a render buffer... amongst other things (tm).
		//   OpenGL will create a unique identifier for a frame vuffer and store it in a GLuint. So we
		//   make a GLuint and pass it to the glGenFramebuffers function to keep this identifier.
		var frameBuffer: GLuint = GLuint()
		glGenFramebuffers(1, &frameBuffer)
		// Then we tell OpenGL that whenever we refer to GL_FRAMEBUFFER, it should treat that as our frameBuffer.
		glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
		// Finally we tell the frame buffer that it's GL_COLOR_ATTACHMENT0 is our colorRenderBuffer. Oh.
		glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderBuffer)
	}
	
	func compileShader(_ shaderName: String, shaderType: GLenum) -> GLuint {
		
		// Get NSString with contents of our shader file.
    guard let shaderPath = Bundle.main.path(forResource: shaderName, ofType: "glsl") else {
      fatalError("Error locating shader file.")
    }

    guard let shaderString = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
      fatalError("Failed to set contents shader of shader file!")
    }

		
		// Tell OpenGL to create an OpenGL object to represent the shader, indicating if it's a vertex or a fragment shader.
		let shaderHandle: GLuint = glCreateShader(shaderType)
		
		// Conver shader string to CString and call glShaderSource to give OpenGL the source for the shader.
    guard var shaderCString = shaderString.cString(using: .utf8) else {
      fatalError("Can not convert shader string.")
    }

    var shaderUTF8StringLength = GLint(shaderCString.count)
    var shaderCStringPtr = UnsafeBufferPointer<GLchar>(start: &shaderCString, count: shaderCString.count).baseAddress
    glShaderSource(shaderHandle, 1, &shaderCStringPtr, &shaderUTF8StringLength)
		
		// Tell OpenGL to compile the shader.
		glCompileShader(shaderHandle)
		
		// But compiling can fail! If we have errors in our GLSL code, we can here and output any errors.
		var compileSuccess: GLint = GLint()
		glGetShaderiv(shaderHandle, GLenum(GL_COMPILE_STATUS), &compileSuccess)
		if (compileSuccess == GL_FALSE) {
			var value: GLint = 0
			glGetShaderiv(shaderHandle, GLenum(GL_INFO_LOG_LENGTH), &value)
			var infoLog: [GLchar] = [GLchar](repeating: 0, count: Int(value))
			var infoLogLength: GLsizei = 0
			glGetShaderInfoLog(shaderHandle, value, &infoLogLength, &infoLog)
      let messageString = String(cString: &infoLog, encoding: String.Encoding.ascii)
			
			print("Failed to compile shader!")
			print(messageString ?? "No Shader compiling message")
			
			exit(1);
		}
		
		return shaderHandle
	}
	
	func compileShaders() {
		
		// Compile our vertex and fragment shaders.
		let vertexShader: GLuint = compileShader("SimpleVertex", shaderType: GLenum(GL_VERTEX_SHADER))
		let fragmentShader: GLuint = compileShader("SimpleFragment", shaderType: GLenum(GL_FRAGMENT_SHADER))
		
		// Call glCreateProgram, glAttachShader, and glLinkProgram to link the vertex and fragment shaders into a complete program.
		let programHandle: GLuint = glCreateProgram()
		glAttachShader(programHandle, vertexShader)
		glAttachShader(programHandle, fragmentShader)
		glLinkProgram(programHandle)
		
		// Check for any errors.
		var linkSuccess: GLint = GLint()
		glGetProgramiv(programHandle, GLenum(GL_LINK_STATUS), &linkSuccess)
		if (linkSuccess == GL_FALSE) {
			fatalError("Failed to create shader program!")
			// TODO: Actually output the error that we can get from the glGetProgramInfoLog function.
		}
		
		// Call glUseProgram to tell OpenGL to actually use this program when given vertex info.
		glUseProgram(programHandle)
		
		// Finally, call glGetAttribLocation to get a pointer to the input values for the vertex shader, so we
		//  can set them in code. Also call glEnableVertexAttribArray to enable use of these arrays (they are disabled by default).
		positionSlot = GLuint(glGetAttribLocation(programHandle, "Position"))
		glEnableVertexAttribArray(positionSlot)
		
		texCoordSlot = GLuint(glGetAttribLocation(programHandle, "TexCoordIn"))
		glEnableVertexAttribArray(texCoordSlot);
		
		textureUniform = GLuint(glGetUniformLocation(programHandle, "Texture"))

//    `time` here is useless
//		timeUniform = GLuint(glGetUniformLocation(programHandle, "time"))

		showShaderBoolUniform = GLuint(glGetUniformLocation(programHandle, "showShader"))
	}
	
	// Setup Vertex Buffer Objects
	func setupVBOs() {
		glGenBuffers(1, &vertexBuffer)
		glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
		glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<(Vertex, Vertex, Vertex, Vertex)>.size, &Vertices, GLenum(GL_STATIC_DRAW))
		
		glGenBuffers(1, &indexBuffer)
		glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBuffer)
		glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), MemoryLayout<(GLubyte, GLubyte, GLubyte, GLubyte, GLubyte, GLubyte)>.size, &Indices, GLenum(GL_STATIC_DRAW))
	}
	
	func setupDisplayLink() {
    let displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(type(of: self).render(displayLink:)))
		displayLink.add(to: .current, forMode: .defaultRunLoopMode)
	}
	
	
	/* Helper Methods
	------------------------------------------*/
	
	func getTextureFromImageWithName(fileName: String) -> GLuint {
		
    guard let spriteImage = UIImage(named: fileName)?.cgImage else {
      fatalError("Failed to load image!")
    }
		
		let width = spriteImage.width, height = spriteImage.height
    let colorSpace = spriteImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let spriteContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
      fatalError("Failedto create CGContext")
    }

    spriteContext.draw(spriteImage, in: CGRect(x: 0, y: 0, width: width, height: height))

		var texName: GLuint = GLuint()
		glGenTextures(1, &texName)
		glBindTexture(GLenum(GL_TEXTURE_2D), texName)

		glTexParameteri(GLenum(GL_TEXTURE), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_NEAREST))
		glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), spriteContext.data)

		return texName
	}
	
	func cleanupVideoTextures() {
    videoTexture = nil

    if let coreVideoTextureCache = coreVideoTextureCache {
      CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0)
    }
	}
	
	func getTextureFromSampleBuffer(_ sampleBuffer: CMSampleBuffer!) -> GLuint {
		cleanupVideoTextures()

    guard let cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer),
      let coreVideoTextureCache = coreVideoTextureCache else {
      fatalError("Can not get camera frame || coreVideoTextureCache")
    }

		textureWidth = CVPixelBufferGetWidth(cameraFrame)
		textureHeight = CVPixelBufferGetHeight(cameraFrame)

		CVPixelBufferLockBaseAddress(cameraFrame, .readOnly)

		guard CVOpenGLESTextureCacheCreateTextureFromImage(
										kCFAllocatorDefault,
										coreVideoTextureCache,
										cameraFrame,
										nil,
										GLenum(GL_TEXTURE_2D),
										GL_RGBA,
										GLsizei(textureWidth),
										GLsizei(textureHeight),
										GLenum(GL_BGRA),
										GLenum(GL_UNSIGNED_BYTE),
										0,
										&videoTexture
      ) == kCVReturnSuccess else {
        fatalError("Error create texture")
    }

    guard let videoTexture = videoTexture else {
      fatalError("Error create texture")
    }
		
		let textureID = CVOpenGLESTextureGetName(videoTexture)
		glBindTexture(GLenum(GL_TEXTURE_2D), textureID);
		
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_CLAMP_TO_EDGE))
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_CLAMP_TO_EDGE))
		
		
		CVPixelBufferUnlockBaseAddress(cameraFrame, .readOnly)
		
		
		return textureID
	}
	
	func updateUsingSampleBuffer(sampleBuffer: CMSampleBuffer!) {

    DispatchQueue.main.async {
      self.videoTextureID = self.getTextureFromSampleBuffer(sampleBuffer)
    }
	}
	
	func shouldShowShader(show: Bool) {
		showShader = show ? 1.0 : 0.0
	}
	
	func render(displayLink: CADisplayLink) {

    if textureWidth == 0 || textureHeight == 0 {
      glViewport(0, 0, GLint(frame.size.width), GLint(frame.size.height))
    } else {
      let ratio = CGFloat(frame.size.height) / CGFloat(textureHeight)
      glViewport(0, 0, GLint(CGFloat(textureWidth) * ratio), GLint(CGFloat(textureHeight) * ratio))
    }

    glClearColor(0, 0, 0, 1)
    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

		glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Vertex>.size), nil)
		glVertexAttribPointer(texCoordSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Vertex>.size), UnsafePointer(bitPattern: MemoryLayout<GLfloat>.stride * 3))
		glActiveTexture(UInt32(GL_TEXTURE0))
		if let videoTextureID = videoTextureID {
			glBindTexture(GLenum(GL_TEXTURE_2D), videoTextureID)
			glUniform1i(GLint(textureUniform), 0)
		}
		
		// Incriment and pass time to shader. This is experimental, be sure to fully test any use of this variable.
//		time += Float(displayLink.duration)
//		glUniform1f(GLint(timeUniform), GLfloat(time))

		glUniform1f(GLint(showShaderBoolUniform), showShader)

		glDrawElements(GLenum(GL_TRIANGLES), 6, GLenum(GL_UNSIGNED_BYTE), nil)
		
		context.presentRenderbuffer(Int(GL_RENDERBUFFER))
	}
}

//
//  WebRTCNS.swift
//  RCTP
//
//  Created by 韦烽传 on 2021/5/17.
//

import Foundation
import AudioToolbox
import WebRTCNS
import Print
import AudioFileInfo

/**
 WebRTC降噪
 */
open class WebRTCNSSwift {
    
    /**
     降噪级别
     */
    public enum Level: Int32 {
        
        /// 低
        case low = 0
        /// 中
        case medium = 1
        /// 高
        case high = 2
        /// 非常高
        case veryHigh = 3
    }
    
    /**
     处理（异步）
     
     1. 仅 8K、16K、32K、48K（不同版本支持的采样率不一样）
     2. 采样率、采样位数、通道数，和原音频一致才能更好的降噪，不然会出现噪音
     3. 无噪音音频，降噪会出现噪音
     
     - parameter    inPath:                 输入音频路径
     - parameter    outPath:                输出音频路径
     - parameter    asbd:                   转换音频参数（输入音频非PCM，需转换为PCM。默认自动转换）
     - parameter    level:                  降噪级别
     - parameter    queue:                  队列
     - parameter    progress:               进度
     - parameter    complete:               成功或失败
     */
    public static func handleAsync(_ inPath: String, outPath: String, asbd: AudioStreamBasicDescription? = nil, level: WebRTCNSSwift.Level = .low, queue: DispatchQueue = DispatchQueue.global(), progress: @escaping (Float)->Void, complete: @escaping (Bool)->Void) {
        
        queue.async {
            
            handle(inPath, outPath: outPath, asbd: asbd, level: level, progress: progress, complete: complete)
        }
    }
    
    /**
     处理
     
     1. 仅 8K、16K、32K、48K（不同版本支持的采样率不一样）
     2. 采样率、采样位数、通道数，和原音频一致才能更好的降噪，不然会出现噪音
     3. 无噪音音频，降噪会出现噪音
     
     - parameter    inPath:                 输入音频路径
     - parameter    outPath:                输出音频路径
     - parameter    asbd:                   转换音频参数（输入音频非PCM，需转换为PCM。默认自动转换）
     - parameter    level:                  降噪级别
     - parameter    progress:               进度
     - parameter    complete:               成功或失败
     */
    public static func handle(_ inPath: String, outPath: String, asbd: AudioStreamBasicDescription? = nil, level: WebRTCNSSwift.Level = .low, progress: @escaping (Float)->Void, complete: @escaping (Bool)->Void) {
        
        /// 状态
        var status: OSStatus = noErr
        
        /// 读取音频文件信息
        guard let readInfo = AudioFileReadInfo(inPath, converter: asbd) else { Print.error("AudioFileReadInfo error"); complete(false); return }
        
        /// 获取音频参数
        var basic = readInfo.basic
        
        /// 使用换音频参数
        if let client = readInfo.client {
            
            basic = client
        }
        
        /// 非PCM 转换 PCM
        if basic.mFormatID != kAudioFormatLinearPCM {
            
            var sampleRate = basic.mSampleRate
            var channels = basic.mChannelsPerFrame
            var bits = basic.mBitsPerChannel
            
            switch sampleRate {
            case 8000, 16000, 32000, 48000:
                break
            default:
                if sampleRate == 0 {
                    sampleRate = 32000
                }
                else if sampleRate < 8000 {
                    sampleRate = 8000
                }
                else if sampleRate < 16000 {
                    sampleRate = 16000
                }
                else if sampleRate < 32000 {
                    sampleRate = 32000
                }
                else if sampleRate < 48000 {
                    sampleRate = 48000
                }
                else {
                    sampleRate = 48000
                }
            }
            
            if channels == 0 {
                channels = 2
            }
            
            if bits == 0 {
                bits = 32
            }
            
            var client = AudioStreamBasicDescription()
            /// 类型
            client.mFormatID = kAudioFormatLinearPCM
            /// flags
            client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            /// 采样率
            client.mSampleRate = sampleRate
            /// 采样位数
            client.mBitsPerChannel = bits
            /// 声道
            client.mChannelsPerFrame = channels
            /// 每个包的帧数
            client.mFramesPerPacket = 1
            /// 每个帧的字节数
            client.mBytesPerFrame = client.mBitsPerChannel / 8 * client.mChannelsPerFrame
            /// 每个包的字节数
            client.mBytesPerPacket = client.mBytesPerFrame * client.mFramesPerPacket
            
            status = ExtAudioFileSetProperty(readInfo.id, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.stride(ofValue: basic)), &client)
            Print.debug("kExtAudioFileProperty_ClientDataFormat \(status)")
            guard status == noErr else { complete(false); return }
            
            basic = client
        }
        
        /// 写入音频文件信息
        guard let writeInfo = AudioFileWriteInfo(outPath, basicDescription: basic) else { Print.debug("AudioFileWriteInfo error"); complete(false); return }
        
        /// 定点降噪
        let nsx = WebRtcNsx_Create()
        
        /**
         关闭资源
         */
        func close() {
            
            WebRtcNsx_Free(nsx);
            ExtAudioFileDispose(readInfo.id)
            ExtAudioFileDispose(writeInfo.id)
        }
        
        /// 初始化降噪
        status = WebRtcNsx_Init(nsx, UInt32(basic.mSampleRate))
        guard status == noErr else { Print.error("WebRtcNsx_Init error"); close(); complete(false); return }
        
        /// 配置降噪
        status = WebRtcNsx_set_policy(nsx, level.rawValue)
        guard status == noErr else { Print.error("WebRtcNsx_set_policy error"); close(); complete(false); return }
        
        /// 读取位置
        var outFramesOffset: Int64 = 0
        
        /// 必须10ms
        let inNumberFrames = UInt32(basic.mSampleRate/100)
        
        /// 开始进度
        progress(0)
        
        while outFramesOffset < readInfo.frames {
            
            var ioNumberFrames = inNumberFrames
            
            /// 初始化`Buffer`
            var ioData = AudioBufferList()
            ioData.mNumberBuffers = 1
            ioData.mBuffers.mDataByteSize = ioNumberFrames * basic.mBytesPerFrame
            ioData.mBuffers.mData = calloc(Int(ioData.mBuffers.mDataByteSize), 1)
            
            /// 读取数据
            var status = ExtAudioFileRead(readInfo.id, &ioNumberFrames, &ioData)
            guard status == noErr else { Print.error("ExtAudioFileRead \(status)"); close(); complete(false); return }
            guard ioNumberFrames == inNumberFrames else { Print.error("ioNumberFrames \(ioNumberFrames) !=  \(inNumberFrames)"); close(); complete(Int64(ioNumberFrames) + outFramesOffset == readInfo.frames); return }
            
            /// 转换`Int16`长度
            let count = Int(ioData.mBuffers.mDataByteSize)/MemoryLayout.stride(ofValue: Int16())
            
            /// 设置`Int16`音频输入
            var inData = [Int16](repeating: 0, count: count)
            memcpy(&inData, ioData.mBuffers.mData, Int(ioData.mBuffers.mDataByteSize))
            /// 设置`Int16`音频输出
            var outData = inData
            
            /**
             降噪（参数转换成指针）
             */
            func process(_ inBytes: UnsafePointer<Int16>?, outBytes: UnsafeMutablePointer<Int16>?) {
                
                var inFrames = inBytes
                var outFrames = outBytes
                
                /// 定点降噪
                WebRtcNsx_Process(nsx, &inFrames, Int32(basic.mChannelsPerFrame), &outFrames)
            }
            
            /// 降噪
            process(&inData, outBytes: &outData)
            
            /// 释放输入音频数据
            free(ioData.mBuffers.mData)
            
            /// 创建输出音频数据
            ioData.mBuffers.mData = calloc(Int(ioData.mBuffers.mDataByteSize), 1)
            ioData.mBuffers.mData?.copyMemory(from: &outData, byteCount: Int(ioData.mBuffers.mDataByteSize))
            
            /// 写入音频文件
            status = ExtAudioFileWrite(writeInfo.id, ioNumberFrames, &ioData)
            guard status == noErr else { Print.error("ExtAudioFileWrite \(status)"); close(); complete(false); return }
            
            /// 释放输出音频数据
            free(ioData.mBuffers.mData)
            
            /// 移动到下个帧片段
            status = ExtAudioFileTell(readInfo.id, &outFramesOffset)
            guard status == noErr else { Print.error("ExtAudioFileTell \(status)"); close(); complete(false); return }
            
            /// 回调进度
            progress(Float(outFramesOffset)/Float(readInfo.frames))
        }
        
        close()
        complete(true)
    }
    
    /// 采样率
    public let sampleRate: UInt32
    /// 采样位数
    public let bitsPer: UInt32
    /// 通道数
    public let channels: Int32
    /// 处理字节数量
    public let handleBytesCount: Int
    /// 降噪级别
    public let level: WebRTCNSSwift.Level
    /// 定点降噪
    private var nsx: OpaquePointer?
    /// 缓冲
    open var buffer: [UInt8] = []
    
    /**
     初始化
     
     1. 仅 8K、16K、32K、48K（不同版本支持的采样率不一样）
     2. 采样率、采样位数、通道数，和原音频一致才能更好的降噪，不然会出现噪音
     3. 无噪音音频，降噪会出现噪音
     
     - parameter    sampleRate:             采样率
     - parameter    bitsPer:                采样位数
     - parameter    channels:               通道数
     - parameter    level:                  降噪级别
     */
    public init?(_ sampleRate: UInt32, bitsPer: UInt32, channels: Int32, level: WebRTCNSSwift.Level = .low) {
        
        self.sampleRate = sampleRate
        self.bitsPer = bitsPer
        self.channels = channels
        self.level = level
        
        handleBytesCount = Int(sampleRate) / 100 * Int(channels) * Int(bitsPer) / 8
        
        /// 定点降噪
        nsx = WebRtcNsx_Create()
        
        /// 状态
        var status: OSStatus = noErr
        
        /// 初始化降噪
        status = WebRtcNsx_Init(nsx, sampleRate)
        guard status == noErr else { Print.error("WebRtcNsx_Init error"); WebRtcNsx_Free(nsx); return nil }
        
        /// 配置降噪
        status = WebRtcNsx_set_policy(nsx, level.rawValue)
        guard status == noErr else { Print.error("WebRtcNsx_set_policy error"); WebRtcNsx_Free(nsx); return nil }
    }
    
    /**
     自动处理
     
     自动分割10毫秒PCM音频数据处理
     不足/剩余不足10毫米数据，保留在缓冲 `buffer` 中，与下个数据连接
     
     - parameter    bytes:  音频数据
     */
    open func automaticHandle(_ bytes: [UInt8]) -> [UInt8] {
        
        var outBytes: [UInt8] = []
        
        buffer += bytes
        
        var start = 0
        var end = handleBytesCount
        
        while buffer.count >= end {
            
            let handleBytes = [UInt8](buffer[start..<end])
            
            outBytes += handle(handleBytes)
            
            start = end
            end += handleBytesCount
        }
        
        if start == buffer.count {
            
            buffer = []
        }
        else {
            
            buffer = [UInt8](buffer[start..<buffer.count])
        }
        
        return outBytes
    }
    
    /**
     处理
     
     音频帧数必须10毫秒PCM音频数据
     字节数 ` bytesCount = sampleRate / 100 * channels * bitsPer / 8`
     
     - parameter    bytes:  音频数据
     */
    open func handle(_ bytes: [UInt8]) -> [UInt8] {
        
        var outBytes = bytes
        
        let inData = Data(bytes: bytes, count: bytes.count)
        
        /// 转换输入指针
        inData.withUnsafeBytes { (inBody: UnsafeRawBufferPointer) -> Void in
            
            let inBind = inBody.bindMemory(to: Int16.self)
            var inBuffer = inBind.baseAddress
            
            var outData = Data(bytes: outBytes, count: outBytes.count)
            
            /// 转换输出指针
            outData.withUnsafeMutableBytes { (outBody: UnsafeMutableRawBufferPointer) -> Void in
                
                let outBind = outBody.bindMemory(to: Int16.self)
                var outBuffer = UnsafeMutablePointer<Int16>.init(outBind.baseAddress)
                
                /// 降噪
                WebRtcNsx_Process(nsx, &inBuffer, channels, &outBuffer)
                
                if let buffer = outBuffer {
                    
                    /// 更新数据
                    outBytes = [UInt8](Data(bytes: buffer, count: bytes.count))
                }
            }
        }
        
        return outBytes
    }
    
    /**
     关闭资源
     */
    open func close() {
        
        WebRtcNsx_Free(nsx);
    }
}

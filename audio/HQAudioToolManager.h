//
//  HQAudioToolManager.h
//  hqedu24olapp
//  
//  Created by panghuijun on 2024/1/3.
//  Copyright © 2024 edu24ol. All rights reserved.
//  音频工具管理者，包括语音听写、语音合成等
    

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HQAudioToolManager : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, copy) void (^recorderVoiceChangeBlock)(NSInteger volume);

- (void)initNuiSDKWithAPPKey:(NSString *)appKey token:(NSString *)token;

/// 开始语音识别
- (void)startRecognizerWithProgress:(void(^)(NSString *result))progress completed:(void(^)(NSString *result, NSString *audioPath, NSError *error))completed;
- (void)startRecognizerWithBegin:(void(^)(NSString *result))begin completed:(void(^)(NSString *result, NSString *audioPath, NSError *error))completed;

/// 停止语音识别
- (void)cancelRecognizer;
- (void)endRecognizer;

/// 开始语音合成
- (void)startSynthesizer:(NSString *)text speakProgress:(void(^)(int progress, int beginPos, int endPos))speakProgress completed:(void(^)(NSString *audioPath, NSError *error))completed;
- (void)pauseSpeaking;
- (void)resumeSpeaking;
/// 停止语音播放
- (void)stopSpeaking;

@end

NS_ASSUME_NONNULL_END

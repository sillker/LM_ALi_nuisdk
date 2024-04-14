//
//  HQAudioToolManager.m
//  hqedu24olapp
//  
//  Created by panghuijun on 2024/1/3.
//  Copyright © 2024 edu24ol. All rights reserved.
//  
    

#import "HQAudioToolManager.h"
#import "nuisdk/NeoNui.h"
#import "NLSVoiceRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AdSupport/ASIdentifierManager.h>
#import "MJExtension/MJExtension.h"
#import <AVFoundation/AVFoundation.h>

//typedef NS_ENUM(NSUInteger, HQAudioTaskType) {
//    HQAudioTaskTypeNone = 0, // 暂无任务
//    HQAudioTaskTypeRecognizer, // 语音识别
//    HQAudioTaskTypeSynthesizer // 语音合成
//};

static BOOL save_wav = YES;
static BOOL save_log = YES;
static dispatch_queue_t sr_work_queue;

@interface HQAudioToolManager()<NlsVoiceRecorderDelegate, NeoNuiSdkDelegate>

@property(nonatomic,strong) NeoNui* nui;
@property(nonatomic,strong) NlsVoiceRecorder *voiceRecorder;
@property(nonatomic,strong) NSMutableData *recordedVoiceData;

/// 当前语音识别录音文本
//@property (nonatomic, copy) NSString *recognizerAudioText;
@property (nonatomic, copy) void(^recognizerCompleted)(NSString *result, NSString *audioPath, NSError *error);
@property (nonatomic, copy) void(^recognizerProgress)(NSString *result);

/// 当前任务(识别器与合成器结束回调方法名相同，因此这里加个区分)
//@property (nonatomic, assign) HQAudioTaskType currentTask;

@end

@implementation HQAudioToolManager

+ (instancetype)sharedInstance
{
    static HQAudioToolManager  *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HQAudioToolManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _voiceRecorder = [[NlsVoiceRecorder alloc] init];
        _voiceRecorder.delegate = self;
        sr_work_queue = dispatch_queue_create("NuiSRController", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)initNuiSDKWithAPPKey:(NSString *)appKey token:(NSString *)token
{
    NSAssert(appKey.length, @"initNuiSDK怎能没有appkey呢");
    NSAssert(token.length, @"initNuiSDK怎么没有token呢");
    if (_nui == NULL) {
        _nui = [NeoNui get_instance];
        _nui.delegate = self;
    }
    
    //请注意此处的参数配置，其中账号相关需要按照genInitParams的说明填入后才可访问服务
    NSString * initParam = [self genInitParamsWithAPPKey:appKey token:token];
    
    NuiResultCode *initCode = [_nui nui_initialize:[initParam UTF8String] logLevel:LOG_LEVEL_VERBOSE saveLog:save_log];
    NSString * parameters = [self genParams];
    NuiResultCode *paramCode = [_nui nui_set_params:[parameters UTF8String]];
    TLog(@"+++ nuisdk init:%d -- setparams:%d",initCode,paramCode);
    TLog(@"+++++ nui SDK 版本：%@", [NSString stringWithUTF8String:[_nui nui_get_version]]);
}

- (NSString*)genInitParamsWithAPPKey:(NSString *)appKey token:(NSString *)token
{
    NSString *bundlePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Resources.bundle"];
    NSString *id_string = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    NSString *debug_path = [self createDir];
    TLog(@"+++ tuisdk device_id: %s", [id_string UTF8String]);

    //获取token方式：
    NSMutableDictionary *dictM = [NSMutableDictionary dictionary];
    [dictM setObject:appKey forKey:@"app_key"];
    [dictM setObject:token  forKey:@"token"];
    [dictM setObject:id_string forKey:@"device_id"]; // 必填, 推荐填入具有唯一性的id, 方便定位问题
    [dictM setObject:@"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1" forKey:@"url"]; // 默认

    //工作目录路径，SDK从该路径读取配置文件
    [dictM setObject:bundlePath forKey:@"workspace"]; // 必填
    //当初始化SDK时的save_log参数取值为true时，该参数生效。表示是否保存音频debug，该数据保存在debug目录中，需要确保debug_path有效可写
    [dictM setObject:save_wav ? @"true" : @"false" forKey:@"save_wav"];
    //debug目录，当初始化SDK时的save_log参数取值为true时，该目录用于保存中间音频文件
    [dictM setObject:debug_path forKey:@"debug_path"];
    
    //FullMix = 0   // 选用此模式开启本地功能并需要进行鉴权注册
    //FullCloud = 1 // 在线实时语音识别可以选这个
    //FullLocal = 2 // 选用此模式开启本地功能并需要进行鉴权注册
    //AsrMix = 3    // 选用此模式开启本地功能并需要进行鉴权注册
    //AsrCloud = 4  // 在线一句话识别可以选这个
    //AsrLocal = 5  // 选用此模式开启本地功能并需要进行鉴权注册
    [dictM setObject:@"4" forKey:@"service_mode"]; // 必填

    NSData *data = [NSJSONSerialization dataWithJSONObject:dictM options:NSJSONWritingPrettyPrinted error:nil];
    NSString * jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return jsonStr;
}

- (NSString*)genParams
{
    NSMutableDictionary *nls_config = [NSMutableDictionary dictionary];
    [nls_config setValue:@YES forKey:@"enable_intermediate_result"]; // 必填
//    参数可根据实际业务进行配置 https://help.aliyun.com/document_detail/173298.html?spm=a2c4g.173528.0.0.47f05398HEpSxW

    //若要使用VAD模式，则需要设置nls_config参数启动在线VAD模式(见genParams())
    //[nls_config setValue:@true forKey:@"enable_voice_detection"];
    //[nls_config setValue:@10000 forKey:@"max_start_silence"];
    //[nls_config setValue:@800 forKey:@"max_end_silence"];

//    [nls_config setValue:@"<更新token>" forKey:@"token"];
//    [nls_config setValue:@true forKey:@"enable_punctuation_prediction"];
//    [nls_config setValue:@true forKey:@"enable_inverse_text_normalization"];

//    [nls_config setValue:@16000 forKey:@"sample_rate"];
//    [nls_config setValue:@"opus" forKey:@"sr_format"];
    NSMutableDictionary *dictM = [NSMutableDictionary dictionary];
    [dictM setObject:nls_config forKey:@"nls_config"];
    [dictM setValue:@(SERVICE_TYPE_ASR) forKey:@"service_type"]; // 必填
//    如果有HttpDns则可进行设置
//    [dictM setObject:[_utils getDirectIp] forKey:@"direct_ip"];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictM options:NSJSONWritingPrettyPrinted error:nil];
    NSString * jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return jsonStr;
}

- (NSString *)dirDoc 
{
    NSString *cacheDirectory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return cacheDirectory;
}


- (NSString *)createDir
{
    NSString *documentsPath = [self dirDoc];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *testDirectory = [documentsPath stringByAppendingPathComponent:@"aliVoices"];
    BOOL res=[fileManager createDirectoryAtPath:testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    if (res) {
        TLog(@"文件夹创建成功");
    }else
        TLog(@"文件夹创建失败");
    return testDirectory;
}


#pragma mark - public

- (void)startRecognizerWithProgress:(void (^)(NSString *))progress completed:(void (^)(NSString *, NSString *, NSError *))completed
{
    // 设置回调
    self.recognizerProgress = progress;
    self.recognizerCompleted = completed;
    
    dispatch_async(sr_work_queue, ^{
        if (_nui != nil) {
            //若要使用VAD模式，则需要设置nls_config参数启动在线VAD模式(见genParams())
            NuiResultCode startCode = [_nui nui_dialog_start:MODE_P2T dialogParam:NULL];
            TLog(@"+++ nuisdk startCode:%d", startCode);
        } else {
            TLog(@"in StartButHandler no nui alloc");
        }
    });
}

- (void)endRecognizer
{
//    self.recordedVoiceData = nil;
    
    if (_nui != nil) {
        [_nui nui_dialog_cancel:NO];
        [_voiceRecorder stop:YES];
    } else {
        TLog(@"in StopButHandler no nui alloc");
    }
    
//    _recognizerProgress = nil;
//    _recognizerCompleted = nil;
    TLog(@"+++++ %s, 结束语音识别", __func__);
}

- (void)cancelRecognizer
{
    self.recordedVoiceData = nil;
    
    _recognizerProgress = nil;
    _recognizerCompleted = nil;
    
    if (_nui != nil) {
        [_nui nui_dialog_cancel:NO];
        [_voiceRecorder stop:YES];
    } else {
        TLog(@"in StopButHandler no nui alloc");
    }
    
    TLog(@"+++++ %s, 取消语音识别", __func__);
}

- (void)startSynthesizer:(NSString *)text speakProgress:(void (^)(int, int, int))speakProgress completed:(void (^)(NSString *, NSError *))completed
{
//    if (!_audioSynthesizer) {
//        [self initSynthesizer];
//    }
//    
//    [_audioSynthesizer stopSpeaking];
    
    // 设置回调
//    _speakProgress = speakProgress;
//    _synthesizerCompleted = completed;
    
    // 设置语音识别录音文件保存路径
//    _synthesizerAudioFileName = [self p_creatAudioFileName];
//    [_audioSynthesizer setParameter:_synthesizerAudioFileName.copy forKey:[IFlySpeechConstant TTS_AUDIO_PATH]];
//    
//    _audioSynthesizer.delegate = self;
    
//    self.currentTask = HQAudioTaskTypeSynthesizer;
        
//    [_audioSynthesizer startSpeaking:text];
}

- (void)pauseSpeaking
{
//    [_audioSynthesizer pauseSpeaking];
}

- (void)resumeSpeaking
{
//    [_audioSynthesizer resumeSpeaking];
}

- (void)stopSpeaking
{
//    [_audioSynthesizer stopSpeaking];
    
//    _speakProgress = nil;
//    _synthesizerCompleted = nil;
}


#pragma mark - Voice Recorder Delegate
- (void)recorderDidStart
{
    TLog(@"recorderDidStart");
}

- (void)recorderDidStop
{
//    [self.recordedVoiceData setLength:0];
    TLog(@"recorderDidStop");
}

- (void)voiceRecorded:(NSData*)frame
{
    @synchronized(_recordedVoiceData){
        [_recordedVoiceData appendData:frame];
    }
}

- (void)voiceDidFail:(NSError*)error
{
    TLog(@"recorder error ");
}

#pragma mark - Nui Listener
///NUI SDK事件回调，请勿在事件回调中调用SDK的接口，可能引起死锁。
-(void)onNuiEventCallback:(NuiCallbackEvent)nuiEvent
                   dialog:(long)dialog
                kwsResult:(const char *)wuw
                asrResult:(const char *)asr_result
                 ifFinish:(bool)finish
                  retCode:(int)code {
    TLog(@"onNuiEventCallback event %d finish %d", nuiEvent, finish);
    if (nuiEvent == EVENT_ASR_PARTIAL_RESULT || nuiEvent == EVENT_ASR_RESULT) {
        TLog(@"ASR RESULT %s finish %d", asr_result, finish);
        NSString *result = [NSString stringWithUTF8String:asr_result];
//        [myself showAsrResult:result];
        /* {"header":{"namespace":"SpeechRecognizer","name":"RecognitionResultChanged","status":20000000,"message_id":"2fda3bfb7fbe4dd5893b36bf6ee5b17e","task_id":"0c969d4259c04b4baab1a7e1b6dbbf34","status_text":"Gateway:SUCCESS:Success."},"payload":{"result":"没有问题来","duration":14193}}
         */
        
        NSDictionary *dict = result.mj_JSONObject;
        dict = [dict objectForKey:@"payload"];
        result = [dict objectForKey:@"result"];
//        _recognizerAudioText = result;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.recognizerCompleted && nuiEvent == EVENT_ASR_RESULT) {
                NSString *audioFilePath = [self createDir];
                self.recognizerCompleted(result, audioFilePath.copy, nil);
            }
            else if (self.recognizerProgress) {
                self.recognizerProgress(result);
            }
        });
    } else if (nuiEvent == EVENT_ASR_ERROR) {
        TLog(@"EVENT_ASR_ERROR error[%d]", code);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.recognizerCompleted) {
                self.recognizerCompleted(nil, nil, nil);
            }
        });
    } else if (nuiEvent == EVENT_MIC_ERROR) {
        TLog(@"MIC ERROR");
        [_voiceRecorder stop:true];
        [_voiceRecorder start];
    }
    
//    else if (nuiEvent == EVENT_VAD_END) {
//        TLog(@"EVENT_VAD_END");
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if (self.recognizerCompleted) {
//                NSString *audioFilePath = [self createDir];
//                self.recognizerCompleted(self.recognizerAudioText, audioFilePath.copy, nil);
//            }
//        });
//    }
    
    return;
}

-(int)onNuiNeedAudioData:(char *)audioData length:(int)len {
    TLog(@"onNuiNeedAudioData");
    static int emptyCount = 0;
    @autoreleasepool {
        @synchronized(_recordedVoiceData){
            if (_recordedVoiceData.length > 0) {
                int recorder_len = 0;
                if (_recordedVoiceData.length > len)
                    recorder_len = len;
                else
                    recorder_len = _recordedVoiceData.length;
                NSData *tempData = [_recordedVoiceData subdataWithRange:NSMakeRange(0, recorder_len)];
                [tempData getBytes:audioData length:recorder_len];
                tempData = nil;
                NSInteger remainLength = _recordedVoiceData.length - recorder_len;
                NSRange range = NSMakeRange(recorder_len, remainLength);
                [_recordedVoiceData setData:[_recordedVoiceData subdataWithRange:range]];
                emptyCount = 0;
                return recorder_len;
            } else {
                if (emptyCount++ >= 50) {
                    TLog(@"_recordedVoiceData length = %lu! empty 50times.", (unsigned long)_recordedVoiceData.length);
                    emptyCount = 0;
                }
                return 0;
            }

        }
    }
    return 0;
}
-(void)onNuiAudioStateChanged:(NuiAudioState)state{
    TLog(@"onNuiAudioStateChanged state=%u", state);
    if (state == STATE_CLOSE || state == STATE_PAUSE) {
        [_voiceRecorder stop:YES];
    } else if (state == STATE_OPEN){
        self.recordedVoiceData = [NSMutableData data];
        [_voiceRecorder start];
    }
}

-(void)onNuiRmsChanged:(float)rms {
    TLog(@"onNuiRmsChanged rms=%f", rms);
}

@end

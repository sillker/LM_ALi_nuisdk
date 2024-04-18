//
//  ChatSoundRecorder.h
//  TIMChat
//
//  Created by AlexiChen on 16/3/17.
//  Copyright © 2016年 AlexiChen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ChatSoundRecorder : NSObject

+  (instancetype)sharedManager;


@property(nonatomic,strong)NSString* recordFileName;  //音频目录
@property(nonatomic,assign)BOOL isRecording;
//开始播放
- (void)startRecord;
//停止播放
- (void)stopRecord;

//获取音量
- (float)getCurrentPower;

@end

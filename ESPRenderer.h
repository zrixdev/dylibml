#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct {
    float x, y, z;
} Vec3;

typedef struct {
    uintptr_t ptr;
    Vec3 pos;
    int32_t hp;
    int32_t hpMax;
    int32_t camp;
    bool isDead;
    bool isSelf;
    int32_t level;
    uint64_t guid;
    float distance;
    CGFloat sx, sy;
    CGFloat boxW, boxH;
    bool onScreen;
} ESPEntity;

int parseEntities(ESPEntity *out, int maxCount);

@interface ESPRenderer : NSObject

+ (instancetype)shared;
- (void)start;
- (void)stop;

@end

#import <UIKit/UIKit.h>

typedef struct {
    CGRect box;
    CGPoint vel;
    float  dist;
    BOOL   ghost;
    CFTimeInterval seen;
} BSTarget;

@interface BSVision : NSObject
+ (instancetype)shared;
- (void)startWithCallback:(void(^)(NSArray *targets))cb;
- (CGPoint)selfPos;
- (float)avgLatency;
- (float)fps;
@property (nonatomic, assign) BOOL calibrating;
@end

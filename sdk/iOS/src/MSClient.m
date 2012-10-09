// ----------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ----------------------------------------------------------------------------
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MSClient.h"
#import "MSTable.h"
#import "MSClientConnection.h"


#pragma mark * MSClient Implementation


@implementation MSClient

@synthesize applicationURL = applicationURL_;
@synthesize applicationKey = applicationKey_;
@synthesize currentUser = currentUser_;

MSClientConnection *connection;

#pragma mark * Public Static Constructor Methods


+(MSClient *) clientWithApplicationURLString:(NSString *)urlString
{
    return [MSClient clientWithApplicationURLString:urlString
                                 withApplicationKey:nil];
}

+(MSClient *) clientWithApplicationURLString:(NSString *)urlString
                           withApplicationKey:(NSString *)key
{
    // NSURL will be nil for non-percent escaped url strings so we have to
    // percent escape here
    NSString  *urlStringEncoded =
    [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *url = [NSURL URLWithString:urlStringEncoded];
    return [MSClient clientWithApplicationURL:url withApplicationKey:key];
}

+(MSClient *) clientWithApplicationURL:(NSURL *)url
{
    return [MSClient clientWithApplicationURL:url withApplicationKey:nil];
}

+(MSClient *) clientWithApplicationURL:(NSURL *)url
                    withApplicationKey:(NSString *)key
{
    return [[MSClient alloc] initWithApplicationURL:url withApplicationKey:key];    
}


#pragma mark * Public Initializer Methods


-(id) initWithApplicationURL:(NSURL *)url
{
    return [self initWithApplicationURL:url withApplicationKey:nil];
}

-(id) initWithApplicationURL:(NSURL *)url withApplicationKey:(NSString *)key
{
    self = [super init];
    if(self)
    {
        applicationURL_ = url;
        applicationKey_ = key;
    }
    return self;
}

#pragma mark * Private Authentication Methods

-(void) parseLoginResponse:(NSData *)response
                 onSuccess:(MSClientLoginSuccessBlock)onSuccess
                   onError:(MSErrorBlock)onError {
    NSError *error;
    id json = [NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
    if (error || ![json isKindOfClass:[NSDictionary class]]) {
        // Token is not a JSON object
        if (onError)
            onError([NSError errorWithDomain:MSErrorDomain
                                        code:MSLoginInvalidResponseSyntax
                                    userInfo:@{@"token": [[NSString alloc] initWithData:response
                                                                               encoding:NSUTF8StringEncoding]}]);
    }
    else {
        id userId = [[json objectForKey:@"user"] objectForKey:@"userId"];
        id authenticationToken = [json objectForKey:@"authenticationToken"];
        if (![userId isKindOfClass:[NSString class]] || ![authenticationToken isKindOfClass:[NSString class]]) {
            // userId or authenticationToken are not strings
            if (onError)
                onError([NSError errorWithDomain:MSErrorDomain
                                            code:MSLoginInvalidResponseSyntax
                                        userInfo:@{@"token": [[NSString alloc] initWithData:response
                                                                                   encoding:NSUTF8StringEncoding]}]);
        }
        else {
            self.currentUser = [[MSUser alloc] initWithUserId:userId];
            self.currentUser.mobileServiceAuthenticationToken = authenticationToken;
            if (onSuccess)
                onSuccess(self.currentUser);
        }
    }
    
}

#pragma mark * Public Authentication Methods

-(MSLoginViewController *) loginViewControllerWithProvider:(NSString *)provider
                                                 onSuccess:(MSClientLoginSuccessBlock)onSuccess
                                                  onCancel:(MSNavigationCancelled)onCancel
                                                   onError:(MSErrorBlock)onError
{
    NSURL* startUrl = [NSURL URLWithString:[NSString stringWithFormat:@"login/%@", provider] relativeToURL:self.applicationURL];
    NSURL* endUrl = [NSURL URLWithString:@"login/done" relativeToURL:self.applicationURL];
    
    __block MSEndUrlNavigatedTo onSuccessWrap = ^(NSURL* url) {
        // The endUrl has been reached
        NSInteger match = [url.absoluteString rangeOfString:@"#token="].location;
        if (match > 0) {
            // Process returned token
            NSString* jsonToken = [[url.absoluteString substringFromIndex:(match + 7)]
                                   stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            [self parseLoginResponse:[jsonToken dataUsingEncoding:NSUTF8StringEncoding]
                           onSuccess:onSuccess
                             onError:onError];
        }
        else if (onError) {
            match = [url.absoluteString rangeOfString:@"#error="].location;
            if (match > 0) {
                // Process error
                onError([NSError errorWithDomain:MSErrorDomain
                                            code:MSLoginFailed
                                        userInfo:@{@"error": [[url.absoluteString substringFromIndex:(match + 7)]
                                                              stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]}]);
            }
            else {
                // Unrecognized response
                onError([NSError errorWithDomain:MSErrorDomain
                                            code:MSLoginInvalidResponseSyntax
                                        userInfo:@{@"error": url.absoluteString}]);
            }
        }
    };
        
    MSLoginViewController* lvc = [[MSLoginViewController alloc]
                                  initWithStartUrl:startUrl
                                  endUrl:endUrl
                                  onSuccess:onSuccessWrap
                                  onCancel:onCancel
                                  onError:onError];
    
    return lvc;
}

-(void) loginWithProvider:(NSString *)provider
                withToken:(NSDictionary *)token
                onSuccess:(MSClientLoginSuccessBlock)onSuccess
                  onError:(MSErrorBlock)onError
{
    if (connection) {
        if (onError)
            onError([NSError errorWithDomain:MSErrorDomain
                                        code:MSLoginAlreadyInProgress
                                    userInfo:nil]);
        return;
    }
    
    NSMutableURLRequest *request = [[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"login/%@", provider]
                                                   relativeToURL:self.applicationURL]] mutableCopy];
    request.HTTPMethod = @"POST";
    NSError *error;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:token options:(0) error:&error];
    if (error) {
        if (onError)
            onError(error);
        return;
    }
    
    __block MSSuccessBlock onSuccessWrap = ^(NSHTTPURLResponse *response, NSData *data) {
        connection = nil;
        [self parseLoginResponse:data onSuccess:onSuccess onError:onError];
    };
    
    __block MSErrorBlock onErrorWrap = ^(NSError *error) {
        connection = nil;
        if (onError)
            onError(error);
    };
    
    connection = [[MSClientConnection alloc] initWithRequest:request
                                                  withClient:self
                                                   onSuccess:onSuccessWrap
                                                     onError:onErrorWrap];
}

-(void) logout
{
    self.currentUser = nil;
}


#pragma mark * Public Table Constructor Methods


-(MSTable *) getTable:(NSString *)tableName
{
    return [[MSTable alloc] initWithName:tableName andClient:self];
}

@end

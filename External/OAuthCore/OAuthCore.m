//
//  OAuthCore.m
//
//  Created by Loren Brichter on 6/9/10.
//  Copyright 2010 Loren Brichter. All rights reserved.
//

#import "OAuthCore.h"
#import "OAuth+Additions.h"
#import "NSData+Base64.h"
#import <CommonCrypto/CommonHMAC.h>
#import "NSString+URIEscaping.h"

static NSInteger SortParameter(NSString *key1, NSString *key2, void *context) {
	NSComparisonResult r = [key1 compare:key2];
	if(r == NSOrderedSame) { // compare by value in this case
		NSDictionary *dict = (__bridge NSDictionary *)context;
		NSString *value1 = [dict objectForKey:key1];
		NSString *value2 = [dict objectForKey:key2];
		return [value1 compare:value2];
	}
	return r;
}

static NSData *HMAC_SHA1(NSString *data, NSString *key) {
	unsigned char buf[CC_SHA1_DIGEST_LENGTH];
	CCHmac(kCCHmacAlgSHA1, [key UTF8String], [key length], [data UTF8String], [data length], buf);
	return [NSData dataWithBytes:buf length:CC_SHA1_DIGEST_LENGTH];
}

NSString *OAuthorizationHeader(NSURL *url, NSString *method, NSData *body, NSString *_oAuthConsumerKey, NSString *_oAuthConsumerSecret, NSString *_oAuthToken, NSString *_oAuthTokenSecret)
{
	NSString *_oAuthNonce = [NSString ab_GUID];
	NSString *_oAuthTimestamp = [NSString stringWithFormat:@"%d", (int)[[NSDate date] timeIntervalSince1970]];
	NSString *_oAuthSignatureMethod = @"HMAC-SHA1";
	NSString *_oAuthVersion = @"1.0";
	
	NSMutableDictionary *oAuthAuthorizationParameters = [NSMutableDictionary dictionary];
	[oAuthAuthorizationParameters setObject:_oAuthNonce forKey:@"oauth_nonce"];
	[oAuthAuthorizationParameters setObject:_oAuthTimestamp forKey:@"oauth_timestamp"];
	[oAuthAuthorizationParameters setObject:_oAuthSignatureMethod forKey:@"oauth_signature_method"];
	[oAuthAuthorizationParameters setObject:_oAuthVersion forKey:@"oauth_version"];
	[oAuthAuthorizationParameters setObject:_oAuthConsumerKey forKey:@"oauth_consumer_key"];
	if(_oAuthToken)
		[oAuthAuthorizationParameters setObject:_oAuthToken forKey:@"oauth_token"];
	
	// get query and body parameters
	NSDictionary *additionalQueryParameters = [NSURL ab_parseURLQueryString:[url query]];
	NSDictionary *additionalBodyParameters = nil;
	if(body) {
		NSString *string = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
		if(string) {
			additionalBodyParameters = [NSURL ab_parseURLQueryString:string];
		}
	}
	
	// combine all parameters
	NSMutableDictionary *parameters = [oAuthAuthorizationParameters mutableCopy];
	if(additionalQueryParameters) [parameters addEntriesFromDictionary:additionalQueryParameters];
	if(additionalBodyParameters) [parameters addEntriesFromDictionary:additionalBodyParameters];
	
	// -> UTF-8 -> RFC3986
	NSMutableDictionary *encodedParameters = [NSMutableDictionary dictionary];
	for(NSString *key in parameters) {
		NSString *value = [parameters objectForKey:key];
		[encodedParameters setObject:[value ab_RFC3986EncodedString] forKey:[key ab_RFC3986EncodedString]];
	}
	
	NSArray *sortedKeys = [[encodedParameters allKeys] sortedArrayUsingFunction:SortParameter context:(__bridge void *)encodedParameters];
	
	NSMutableArray *parameterArray = [NSMutableArray array];
	for(NSString *key in sortedKeys) {
		[parameterArray addObject:[NSString stringWithFormat:@"%@=%@", key, [encodedParameters objectForKey:key]]];
	}
	NSString *normalizedParameterString = [parameterArray componentsJoinedByString:@"&"];
	
	NSString *normalizedURLString = [NSString stringWithFormat:@"%@://%@%@", [url scheme], [url host], [NSString escapePath:[url path]]];
	
	NSString *signatureBaseString = [NSString stringWithFormat:@"%@&%@&%@",
									 [method ab_RFC3986EncodedString],
									 [normalizedURLString ab_RFC3986EncodedString],
									 [normalizedParameterString ab_RFC3986EncodedString]];
  
	NSString *key = [NSString stringWithFormat:@"%@&%@",
					 [_oAuthConsumerSecret ab_RFC3986EncodedString],
					 [_oAuthTokenSecret ab_RFC3986EncodedString]];
	
	NSData *signature = HMAC_SHA1(signatureBaseString, key);
	NSString *base64Signature = [signature base64EncodedString];
	
	NSMutableDictionary *authorizationHeaderDictionary = [oAuthAuthorizationParameters mutableCopy];
	[authorizationHeaderDictionary setObject:base64Signature forKey:@"oauth_signature"];
	
	NSMutableArray *authorizationHeaderItems = [NSMutableArray array];
	for(NSString *key in authorizationHeaderDictionary) {
		NSString *value = [authorizationHeaderDictionary objectForKey:key];
		[authorizationHeaderItems addObject:[NSString stringWithFormat:@"%@=\"%@\"",
											 [key ab_RFC3986EncodedString],
											 [value ab_RFC3986EncodedString]]];
	}
	
	NSString *authorizationHeaderString = [authorizationHeaderItems componentsJoinedByString:@", "];
	authorizationHeaderString = [NSString stringWithFormat:@"OAuth %@", authorizationHeaderString];
	
	return authorizationHeaderString;
}

extern NSString *OAuth2Header(NSURL *url, 
                              NSString *method, NSInteger port,
                              NSString *_oAuthConsumerKey, 
                              NSString *_oAuthConsumerSecret, 
                              NSString *_oAuthToken, 
                              NSString *_oAuthTokenSecret)
{
	NSString *oAuth2Nonce = [NSString ab_GUID];
	NSString *oAuth2Timestamp = [NSString stringWithFormat:@"%d", (int)[[NSDate date] timeIntervalSince1970]];

  NSMutableString *normalizedString = [[NSMutableString alloc] init];
  
  [normalizedString appendFormat:@"%@\n", _oAuthToken];
  [normalizedString appendFormat:@"%@\n", oAuth2Timestamp];
  [normalizedString appendFormat:@"%@\n", oAuth2Nonce];
  [normalizedString appendFormat:@"%@\n", method];
  [normalizedString appendFormat:@"%@\n", [url host]];
  [normalizedString appendFormat:@"%d\n", port];
  [normalizedString appendFormat:@"%@\n", [url path]];

  
  NSData *signature = HMAC_SHA1(normalizedString, _oAuthTokenSecret);
	NSString *base64Signature = [signature base64EncodedString];

  NSString *authorizationString = [NSString stringWithFormat:@"MAC token=\"%@\", timestamp=\"%@\", nonce=\"%@\", signature=\"%@\"", _oAuthToken, oAuth2Timestamp, oAuth2Nonce, base64Signature];
  
  return authorizationString;
}



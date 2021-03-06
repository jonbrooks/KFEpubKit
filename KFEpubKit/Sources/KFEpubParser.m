//  KFEpubParser.m
//  KFEpubKit
//
// Copyright (c) 2013 Rico Becker | KF INTERACTIVE
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "KFEpubParser.h"


@interface KFEpubParser ()


@property (strong) NSXMLParser *parser;
@property (strong) NSString *rootPath;
@property (strong) NSMutableDictionary *items;
@property (strong) NSMutableArray *spinearray;


@end


#define kMimeTypeEpub @"application/epub+zip"
#define kMimeTypeiBooks @"application/x-ibooks+zip"


@implementation KFEpubParser


- (KFEpubKitBookType)bookTypeForBaseURL:(NSURL *)baseURL
{
    NSError *error = nil;
    KFEpubKitBookType bookType = KFEpubKitBookTypeUnknown;
    
    NSURL *mimetypeURL = [baseURL URLByAppendingPathComponent:@"mimetype"];
    NSString *mimetype = [[NSString alloc] initWithContentsOfURL:mimetypeURL encoding:NSASCIIStringEncoding error:&error];
    
    if (error)
    {
        return bookType;
    }
    
    NSRange mimeRange = [mimetype rangeOfString:kMimeTypeEpub];
    
    if (mimeRange.location == 0 && mimeRange.length == 20)
    {
        bookType = KFEpubKitBookTypeEpub2;
    }
    else if ([mimetype isEqualToString:kMimeTypeiBooks])
    {
        bookType = KFEpubKitBookTypeiBook;
    }
    
    return bookType;
}


- (KFEpubKitBookEncryption)contentEncryptionForBaseURL:(NSURL *)baseURL
{
    NSURL *containerURL = [[baseURL URLByAppendingPathComponent:@"META-INF"] URLByAppendingPathComponent:@"sinf.xml"];
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:containerURL encoding:NSUTF8StringEncoding error:&error];
    DDXMLDocument *document = [[DDXMLDocument alloc] initWithXMLString:content options:kNilOptions error:&error];
    
    if (error)
    {
        return KFEpubKitBookEnryptionNone;
    }
    NSArray *sinfNodes = [document.rootElement nodesForXPath:@"//fairplay:sinf" error:&error];
    if (sinfNodes == nil || sinfNodes.count == 0)
    {
        return KFEpubKitBookEnryptionNone;
    }
    else
    {
        return KFEpubKitBookEnryptionFairplay;
    }
}


- (NSURL *)rootFileForBaseURL:(NSURL *)baseURL
{
    NSError *error = nil;
    NSURL *containerURL = [[baseURL URLByAppendingPathComponent:@"META-INF"] URLByAppendingPathComponent:@"container.xml"];
    
    NSString *content = [NSString stringWithContentsOfURL:containerURL encoding:NSUTF8StringEncoding error:&error];
    DDXMLDocument *document = [[DDXMLDocument alloc] initWithXMLString:content options:kNilOptions error:&error];
    DDXMLElement *root  = [document rootElement];
    
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray* objectElements = [root nodesForXPath:@"//default:container/default:rootfiles/default:rootfile" error:&error];
    
    NSUInteger count = 0;
    NSString *value = nil;
    for (DDXMLElement* xmlElement in objectElements)
    {
        value = [[xmlElement attributeForName:@"full-path"] stringValue];
        count++;
    }

    if (count == 1 && value)
    {
        return [baseURL URLByAppendingPathComponent:value];
    }
    else if (count == 0)
    {
        NSLog(@"no root file found.");
    }
    else
    {
        NSLog(@"there are more than one root files. this is odd.");
    }
    return nil;
}


- (NSString *)coverPathComponentFromDocument:(DDXMLDocument *)document
{
    NSString *coverPath;
    DDXMLElement *root  = [document rootElement];
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *metaNodes = [root nodesForXPath:@"//default:item[@properties='cover-image']" error:nil];
    
    if (metaNodes)
    {
        coverPath = [[metaNodes.lastObject attributeForName:@"href"] stringValue];
    }
    
    if (!coverPath)
    {
        NSString *coverItemId;
        
        DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
        defaultNamespace.name = @"default";
        metaNodes = [root nodesForXPath:@"//default:meta" error:nil];
        for (DDXMLElement *xmlElement in metaNodes)
        {
            if ([[xmlElement attributeForName:@"name"].stringValue compare:@"cover" options:NSCaseInsensitiveSearch] == NSOrderedSame)
            {
                coverItemId = [xmlElement attributeForName:@"content"].stringValue;
            }
        }
        
        if (!coverItemId)
        {
            return nil;
        }
        else
        {
            DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
            defaultNamespace.name = @"default";
            NSArray *itemNodes = [root nodesForXPath:@"//default:item" error:nil];
            
            for (DDXMLElement *itemElement in itemNodes)
            {
                if ([[itemElement attributeForName:@"id"].stringValue compare:coverItemId options:NSCaseInsensitiveSearch] == NSOrderedSame)
                {
                    coverPath = [itemElement attributeForName:@"href"].stringValue;
                }
            }
            
        }
    }
    return coverPath;
}



- (NSDictionary *)metaDataFromDocument:(DDXMLDocument *)document
{
    NSMutableDictionary *metaData = [NSMutableDictionary new];
    DDXMLElement *root  = [document rootElement];
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *metaNodes = [root nodesForXPath:@"//default:package/default:metadata" error:nil];
    
    if (metaNodes.count == 1)
    {
        DDXMLElement *metaNode = metaNodes[0];
        NSArray *metaElements = metaNode.children;

        for (DDXMLElement* xmlElement in metaElements)
        {
            if ([self isValidNode:xmlElement])
            {
                metaData[xmlElement.localName] = xmlElement.stringValue;
            }
        }
    }
    else
    {
        NSLog(@"meta data invalid");
        return nil;
    }
    return metaData;
}


- (NSArray *)spineFromDocument:(DDXMLDocument *)document
{
    NSMutableArray *spine = [NSMutableArray new];
    DDXMLElement *root  = [document rootElement];
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *spineNodes = [root nodesForXPath:@"//default:package/default:spine" error:nil];
    
    if (spineNodes.count == 1)
    {
        DDXMLElement *spineElement = spineNodes[0];
        
        NSString *toc = [[spineElement attributeForName:@"toc"] stringValue];
        if (toc)
        {
            //The toc is a special item, which really shouldn't be included in the spine items.
            //Rather than reengineer KFEpubParser, we just mark it as non-linear.
            [spine addObject:@{ @"idref": toc,
                                @"linear" : @(NO)}];
        }
        else
        {
            [spine addObject:@{ @"idref": @"",
                                @"linear" : @(NO)}];
        }
        NSArray *spineElements = spineElement.children;
        for (DDXMLElement* xmlElement in spineElements)
        {
            if ([self isValidNode:xmlElement])
            {
                NSString *idref = [[xmlElement attributeForName:@"idref"] stringValue];
                
                //If linear property is not present, default is true
                BOOL isLinear = YES;
                
                NSString *linearValue = [[xmlElement attributeForName:@"linear"] stringValue];
                
                if (linearValue) {
                    isLinear = [linearValue boolValue];
                }
                
                [spine addObject:@{ @"idref": idref,
                                    @"linear" : @(isLinear)}];
            }
        }
    }
    else
    {
        NSLog(@"spine data invalid");
        return nil;
    }
    return spine;
}


- (NSDictionary *)manifestFromDocument:(DDXMLDocument *)document
{
    NSMutableDictionary *manifest = [NSMutableDictionary new];
    DDXMLElement *root  = [document rootElement];
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *manifestNodes = [root nodesForXPath:@"//default:package/default:manifest" error:nil];
    
    if (manifestNodes.count == 1)
    {
        NSArray *itemElements = ((DDXMLElement *)manifestNodes[0]).children;
        for (DDXMLElement* xmlElement in itemElements)
        {
            if ([self isValidNode:xmlElement] && xmlElement.attributes)
            {
                NSString *href = [[xmlElement attributeForName:@"href"] stringValue];
                NSString *itemId = [[xmlElement attributeForName:@"id"] stringValue];
                NSString *mediaType = [[xmlElement attributeForName:@"media-type"] stringValue];
                
                if (itemId)
                {
                    NSMutableDictionary *items = [NSMutableDictionary new];
                    if (href)
                    {
                        items[@"href"] = href;
                    }
                    if (mediaType)
                    {
                        items[@"media"] = mediaType;
                    }
                    manifest[itemId] = items;
                }
            }
        }
    }
    else
    {
        NSLog(@"manifest data invalid");
        return nil;
    }
    return manifest;
}


- (NSArray *)guideFromDocument:(DDXMLDocument *)document
{
    NSMutableArray *guide = [NSMutableArray new];
    DDXMLElement *root  = [document rootElement];
    
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *guideNodes = [root nodesForXPath:@"//default:package/default:guide" error:nil];
    
    if (guideNodes.count == 1)
    {
        DDXMLElement *guideElement = guideNodes[0];
        NSArray *referenceElements = guideElement.children;
        
        for (DDXMLElement* xmlElement in referenceElements)
        {
            if ([self isValidNode:xmlElement])
            {
                NSString *type = [[xmlElement attributeForName:@"type"] stringValue];
                NSString *href = [[xmlElement attributeForName:@"href"] stringValue];
                NSString *title = [[xmlElement attributeForName:@"title"] stringValue];
                
                NSMutableDictionary *reference = [NSMutableDictionary new];
                if (type)
                {
                    reference[type] = type;
                }
                if (href)
                {
                    reference[@"href"] = href;
                }
                if (title)
                {
                    reference[@"title"] = title;
                }
                [guide addObject:reference];
            }
        }
    }
    else
    {
        NSLog(@"guide data invalid");
        return nil;
    }
    
    return guide;
}

- (NSArray *)tocFromDocument:(DDXMLDocument *)document
{
    NSMutableArray *toc = [NSMutableArray array];
    
    DDXMLElement *root  = [document rootElement];
    DDXMLNode *defaultNamespace = [root namespaceForPrefix:@""];
    defaultNamespace.name = @"default";
    NSArray *mapNodes = [root nodesForXPath:@"//default:navMap" error:nil];
    
    if ([mapNodes count] == 1)
    {
        NSArray *itemElements = ((DDXMLElement *)mapNodes[0]).children;
        
        [self findTocItemsFrom:itemElements addTo:toc atLevel:1];
    }
    else
    {
        NSLog(@"map data invalid");
    }
    
    return toc;
}

- (void)findTocItemsFrom:(NSArray *)elements addTo:(NSMutableArray *)toc atLevel:(NSInteger)level
{
    if (elements == nil || [elements count] == 0) return;
    
    for (DDXMLElement *xmlElement in elements)
    {
        NSString *title = nil;
        NSString *href = nil;
        
        NSArray *e;
        
        // retrieve the title
        e = [xmlElement elementsForName:@"navLabel"];
        if ([e count] == 1)
        {
            e = [e[0] elementsForName:@"text"];
            if ([e count] == 1)
            {
                title = [e[0] stringValue];
            }
            else
            {
                NSLog(@"toc data invalid (text)");
            }
        }
        else
        {
            NSLog(@"toc data invalid (navLabel)");
        }
        
        // retrieve the href
        e = [xmlElement elementsForName:@"content"];
        if ([e count] == 1)
        {
            href = [[e[0] attributeForName:@"src"] stringValue];
        }
        else
        {
            NSLog(@"toc data invalid (content)");
        }
        
        // add toc entry
        if (href && title)
        {
            [toc addObject:@{@"href" : href,
                             @"title" : title,
                             @"level" : @(level)}];
        }
        
        // retrieve toc items at the next level
        e = [xmlElement elementsForName:@"navPoint"];
        [self findTocItemsFrom:e addTo:toc atLevel:level+1];
    }
}

- (BOOL)isValidNode:(DDXMLElement *)node
{
    return node.kind != DDXMLCommentKind;
}


@end

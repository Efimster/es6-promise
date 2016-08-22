//
//  Promise.swift
//  Promises
//
//  Created by Efim Goncharuk on 8/2/16.
//  Copyright © 2016 Efim Goncharuk. All rights reserved.
//

public class Promise<T>{
    //MARK: properties
    
    public private(set) var resolvedValue:T? = nil
    public private(set) var rejectReason:Error? = nil
    public private(set) var state:State = .pending
    var fulfilmentHandler:((T)throws->Promise<T>)?
    var rejectionHandler:((Error)->Promise<T>)?
    var chainPromise:Promise<T>?
    
    //MARK: static functions
    

    public static func resolve(value:T)->Promise<T>{
        let promise = Promise()
        promise.onFulfilled(value:value)
        return promise
    }
    
    public static func reject(reason:Error)->Promise<T>{
        let promise = Promise()
        promise.onRejected(reason:reason)
        return promise
    }
    
    public static func all<S:Sequence>(promises:S)->Promise<[T]> where S.Iterator.Element == Promise<T>{
        let result = Promise<[T]>()
        var arrayOfPromises:[Promise<T>] = []
        var resolvedCount = 0
        
        for promise in promises{
            if promise.state == .rejected{
                result.onRejected(reason:promise.rejectReason!)
                return result
            }
            
            arrayOfPromises.append(promise)
        }
        
        var resolvedValues:Array<T?> = [T?](repeating:nil, count:arrayOfPromises.count)
        
        for (index, promise) in arrayOfPromises.enumerated(){
             let _ = promise
                .then(onFulfilled:{(value:T)->Void in
                    if result.state != .pending {
                        return
                    }

                    resolvedCount += 1
                    resolvedValues[index] = value
                    if arrayOfPromises.count == resolvedCount {
                        result.onFulfilled(value:resolvedValues.map({$0!}))
                    }
                }, onRejected:{(reason:Error)->Void in
                    if result.state != .pending {
                        return
                    }
                    result.onRejected(reason:reason)
                })
        }

        return result
    }
    
    public static func race<S:Sequence>(promises:S)->Promise<T> where S.Iterator.Element == Promise<T>{
        let result = Promise<T>()
        
        for promise in promises{
            let _ = promise.then(onFulfilled:{(value:T)->Void in
                if result.state != .pending {
                    return
                }
                result.onFulfilled(value:value)
            }, onRejected:{(reason:Error)->Void in
                if result.state != .pending {
                    return
                }
                result.onRejected(reason:reason)
            })
        }
        return result
    }
    
    private static func normalizeVoidHandler(reject handler:@escaping (Error)->Void)->(Error)->Promise<T>{
        return {(reason:Error)->Promise<T> in
            handler(reason)
            return Promise.reject(reason: reason)
        }
    }
    
    private static func normalizeVoidHandler(resolve handler:@escaping (T)->Void)->(T)->Promise<T>{
        return {(value:T)->Promise<T> in
            handler(value)
            return Promise.resolve(value: value)
        }
    }
    
    // MARK: initializers
    
    private init() {}
    
    public init(_ executor:(@escaping (T)->Void, @escaping (Error)->Void)throws->Void){
        do {
            try executor(onFulfilled, onRejected)
        } catch {
            onRejected(reason:error)
        }
    }
    
    public init(_ executor:(@escaping (T)->Void)throws->Void){
        do {
            try executor(onFulfilled)
        } catch {
            onRejected(reason:error)
        }
    }
    
    // MARK: methods

    public func then(onFulfilled resolve:@escaping (T)throws->Promise<T>)->Promise<T>{
        return then(onFulfilled:resolve, onRejected:{reason in self})
    }
    
    public func then(onFulfilled resolve:@escaping (T)throws->Promise<T>, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        if state == .fulfilled {
            do {
                return try resolve(resolvedValue!)
            } catch {
                onRejected(reason:error)
            }
        }
        else if state == .rejected {
            return reject(rejectReason!)
        }
        
        fulfilmentHandler = resolve
        rejectionHandler = reject
        let promise = Promise()
        self.chainPromise = promise
        return promise
    }
    
    public func then(onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onFulfilled:{resolvingValue in self}, onRejected:reject)
    }
    
    public func then(onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onRejected:Promise.normalizeVoidHandler(reject: reject))
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        })
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T, onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        }, onRejected:Promise.normalizeVoidHandler(reject:reject))
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        }, onRejected:reject)
    }
    
    public func then(onFulfilled resolve:@escaping (T)->Void)->Promise<T>{
        return then(onFulfilled:Promise.normalizeVoidHandler(resolve: resolve))
    }

    public func then(onFulfilled resolve:@escaping (T)->Void, onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onFulfilled:Promise.normalizeVoidHandler(resolve: resolve), onRejected:Promise.normalizeVoidHandler(reject:reject))
    }
    
    public func then(onFulfilled resolve:@escaping (T)->Void, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onFulfilled:Promise.normalizeVoidHandler(resolve: resolve), onRejected:reject)
    }
    
    public func `catch`(onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onRejected:reject)
    }
    
    public func `catch`(onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onRejected:Promise.normalizeVoidHandler(reject:reject))
    }
    
    private func onFulfilled(value:T)->Void {
        if let fulfilmentHandler = self.fulfilmentHandler {
            self.rejectionHandler = nil;
            self.fulfilmentHandler = nil;
            
            let fulfillmentPromise:Promise<T>?
            do {
                fulfillmentPromise =  try fulfilmentHandler(value)
            } catch {
                onRejected(reason:error)
                return
            }
            
            let _ = fulfillmentPromise!.then(onFulfilled:{value in
                    self.chainPromise?.onFulfilled(value: value)
                }, onRejected:{reason in
                    self.chainPromise?.onRejected(reason: reason)
                }
            )
        }
        else{
            state = .fulfilled;
            resolvedValue = value;
        }
    }
    
    private func onRejected(reason:Error)->Void{
        if let rejectionHandler = self.rejectionHandler {
            self.rejectionHandler = nil;
            self.fulfilmentHandler = nil;
            let rejectionPromise = rejectionHandler(reason)
            
            let _ = rejectionPromise.then(onFulfilled:{value in
                    self.chainPromise?.onFulfilled(value: value)
                }, onRejected:{reason in
                    self.chainPromise?.onRejected(reason: reason)
                }
            )
        }
        else{
            state = .rejected;
            rejectReason = reason;
        }
    }
}

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
    var upChainPromise:Promise<T>?
    
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
    
    private static func normalizeVoidHandler(reject handler:@escaping (Error)->Void, forPromise promise:Promise<T>)->(Error)->Promise<T>{
        return {(reason:Error)->Promise<T> in
            handler(reason)
            return promise
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
        if state == .fulfilled {
            do {
                return try resolve(resolvedValue!)
            } catch {
                onRejected(reason:error)
            }
        }
        
        fulfilmentHandler = resolve
        return self
    }
    
    public func then(onFulfilled resolve:@escaping (T)throws->Promise<T>, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        if state == .fulfilled {
            return then(onFulfilled:resolve)
        }
        else if state == .rejected {
            return reject(rejectReason!)
        }
        
        fulfilmentHandler = resolve
        rejectionHandler = reject
        return self
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        })
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T, onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        }, onRejected:Promise.normalizeVoidHandler(reject:reject, forPromise:self))
    }
    
    public func then(onFulfilled resolve:@escaping (T)->T, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            return Promise.resolve(value:resolve(resolvingValue))
        }, onRejected:reject)
    }
    
    public func then(onFulfilled resolve:@escaping (T)->Void)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            resolve(resolvingValue)
            return self
        })
    }

    public func then(onFulfilled resolve:@escaping (T)->Void, onRejected reject:@escaping (Error)->Void)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            resolve(resolvingValue)
            return self
        }, onRejected:Promise.normalizeVoidHandler(reject:reject, forPromise:self))
    }
    
    public func then(onFulfilled resolve:@escaping (T)->Void, onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        return then(onFulfilled:{(resolvingValue:T)->Promise<T> in
            resolve(resolvingValue)
            return self
        }, onRejected:reject)
    }

    
    private func onFulfilled(value:T) -> Void {
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
            
            if fulfillmentPromise! === self {
                state = .fulfilled;
                resolvedValue = value;
                return
            }

            if fulfillmentPromise!.state == .pending{
                fulfillmentPromise!.upChainPromise = self
            }
            else if fulfillmentPromise!.state == .fulfilled {
                onFulfilled(value:fulfillmentPromise!.resolvedValue!)
            }
            else if fulfillmentPromise!.state == .rejected {
                onRejected(reason: fulfillmentPromise!.rejectReason!)
            }
        }
        else{
            state = .fulfilled;
            resolvedValue = value;
        }

        if let fulfillmentUpChainPromise = self.upChainPromise {
            fulfillmentUpChainPromise.onFulfilled(value:value)
        }
    }
    
    public func `catch`(onRejected reject:@escaping (Error)->Promise<T>)->Promise<T>{
        if state == .rejected {
            return reject(rejectReason!)
        }
        
        rejectionHandler = reject
        return self
    }
    
    public func `catch`(onRejected reject:@escaping (Error)->Void)->Promise<T>{
        let onRejected =  Promise.normalizeVoidHandler(reject:reject, forPromise:self)
        return `catch`(onRejected:onRejected)
    }
    
    private func onRejected(reason:Error)->Void{
        if let rejectionHandler = self.rejectionHandler {
            self.rejectionHandler = nil;
            self.fulfilmentHandler = nil;
            let rejectionPromise = rejectionHandler(reason)
            
            if rejectionPromise === self {
                state = .rejected;
                rejectReason = reason;
                return
            }
            
            if rejectionPromise.state == .pending{
                rejectionPromise.upChainPromise = self
            }
            else if rejectionPromise.state == .rejected {
                onRejected(reason:rejectionPromise.rejectReason!)
            }
            else if rejectionPromise.state == .fulfilled {
                onFulfilled(value:rejectionPromise.resolvedValue!)
            }
            
        }
        else{
            state = .rejected;
            rejectReason = reason;
        }
        
        if let rejectionUpChainPromise = self.upChainPromise {
            rejectionUpChainPromise.onRejected(reason:reason)
        }
    }
}

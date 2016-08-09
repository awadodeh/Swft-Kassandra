/**
 Copyright IBM Corporation 2016
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

public protocol Query {
    func pack() -> Data
}

extension Query {

    public func execute() -> Promise<TableObj> {
        let p = Promise<TableObj>.deferred()
    
        let request: Request = .query(using: self)
        
        do {
            try config.connection?.execute(request) {
                result, error in
                
                if let error = error { p.reject(dueTo: error) }
                if let res = result { p.resolve()(res) }
            }
        } catch {
            p.reject(dueTo: error)

        }

        return p
    }

    public func execute(oncompletion: ((Error?) -> Void)) throws {
        
        let request: Request = .query(using: self)
        
        try config.connection?.execute(request, oncompletion: oncompletion)
    }
}

public enum Order: String {
    case ASC = "ASC"
    case DESC = "DESC"
}
public enum Flags: Byte {
    case none = 0x00
    case compression = 0x01
    case tracing = 0x02
    case all = 0x03
    
}
public enum SQLFunction<T> {
    case max([T])
    case min([T])
    case avg([T])
    case sum([T])
    case count([T])
    
    func pack() -> String {
        switch self {
        case .max(let args)     : return args.count == 0 ? "MAX(*)" : "MAX(\(args.map{ String(describing: $0) }.joined(separator: ", ")))"
        case .min(let args)     : return args.count == 0 ? "MIN(*)" : "MIN(\(args.map{ String(describing: $0) }.joined(separator: ", ")))"
        case .avg(let args)     : return args.count == 0 ? "AVG(*)" : "AVG(\(args.map{ String(describing: $0) }.joined(separator: ", ")))"
        case .sum(let args)     : return args.count == 0 ? "SUM(*)" : "SUM(\(args.map{ String(describing: $0) }.joined(separator: ", ")))"
        case .count(let args)   : return args.count == 0 ? "COUNT(*)" : "COUNT(\(args.map{ String(describing: $0) }.joined(separator: ", ")))"
        }
    }
}

public struct Select: Query {
    
    let tableName: String
    
    let fields: [String]
    
    var order: [String: Order]? = nil
    
    var conditions: Predicate? = nil

    var limitResultCount: Int? = nil
    
    var sqlfunction: SQLFunction<String>? = nil
    
    var consistency: Consistency
    
    var flags: Flags = .none

    public init(_ fields: [String], from tableName: String, consistency: Consistency = .one) {
        self.fields = fields
        self.tableName = tableName
        self.consistency = consistency
    }
    
    private mutating func order(by predicate: [String: Order]) {
        order = predicate
    }

    public func ordered(by predicate: [String: Order]) -> Select {
        var new = self
        new.order(by: predicate)
        return self
    }

    private mutating func limit(to newLimit: Int) {
        limitResultCount = newLimit
    }

    public func limited(to newLimit: Int) -> Select {
        var new = self
        new.limit(to: newLimit)
        return self
    }

    public mutating func filtered(by conditions: Predicate) {
        self.conditions = conditions
    }

    public func filter(by conditions: Predicate) -> Select {
        var new = self
        new.filtered(by: conditions)
        return self
    }
    
    public mutating func set(consistency: Consistency = .any, flags: Flags = .none) {
        self.flags = flags
        self.consistency = consistency
    }

    public func with(consistency: Consistency = .any, flags: Flags = .none) -> Select {
        var new = self
        new.set(consistency: consistency, flags: flags)
        return self
    }

    public func pack() -> Data {
        var data = Data()
        
        data.append(buildQueryString.longStringData)
        data.append(consistency.rawValue.data)
        data.append(flags.rawValue.data)
        
        return data
    }

    private var buildQueryString: String {
        var str = "SELECT "
        
        if let function = sqlfunction?.pack() {
            fields.count == 0 ? (str += "\(function) FROM \(tableName)") :
                (str += "\(function), \(fields.joined(separator: " ")) FROM \(tableName)")
        } else {
            fields.count == 0 ? (str += "* FROM \(tableName)") :
                (str += "\(fields.joined(separator: " ")) FROM \(tableName)")
        }
        
        if let cond = conditions {
            str += " WHERE " + cond.str
        }
        if let order = order {
            str += " ORDER BY " + order.map {key, val in "\(key) \(val.rawValue)" }.joined(separator: ", ")
        }
        if let limit = limitResultCount {
            str += " LIMIT \(limit)"
        }
        
        return str + ";"
        
    }
}
public struct Update: Query {
    
    let tableName: String
    
    let newValues: [String: Any]

    var conditions: Predicate
    
    var consistency: Consistency
    
    var flags: Flags = .none

    public init(to newValues: [String: Any], in tableName: String, where predicate: Predicate, consistency: Consistency = .any) {
        self.newValues = newValues
        self.tableName = tableName
        self.conditions = predicate
        self.consistency = consistency
    }
    
    public mutating func filter(by predicate: Predicate){
        conditions = predicate
    }

    public mutating func set(consistency: Consistency = .any, flags: Flags = .none) {
        self.flags = flags
        self.consistency = consistency
    }
    
    public func with(consistency: Consistency = .any, flags: Flags = .none) -> Update {
        var new = self
        new.set(consistency: consistency, flags: flags)
        return self
    }

    public func pack() -> Data {
        var data = Data()

        let vals  = packPairs(newValues)
        let conds = conditions.str

        data.append(("UPDATE \(tableName) SET \(vals) WHERE \(conds);").longStringData)
        

        data.append(consistency.rawValue.data)
        data.append(flags.rawValue.data)
        
        return data
    }
    
}
public struct Delete: Query {

    let tableName: String
    
    let conditions: Predicate
    
    var consistency: Consistency

    var flags: Flags = .none

    public init(from tableName: String, where condition: Predicate, consistency: Consistency = .any) {
        self.conditions = condition
        self.tableName = tableName
        self.consistency = consistency
    }

    public mutating func set(consistency: Consistency = .any, flags: Flags = .none) {
        self.flags = flags
        self.consistency = consistency
    }
    
    public func with(consistency: Consistency = .any, flags: Flags = .none) -> Delete {
        var new = self
        new.set(consistency: consistency, flags: flags)
        return self
    }

    public func pack() -> Data {
        var data = Data()

        let conds = conditions.str
        
        data.append(("DELETE FROM \(tableName) WHERE \(conds);").longStringData)
        data.append(consistency.rawValue.data)
        data.append(flags.rawValue.data)
        
        return data
    }
}
public struct Insert: Query {
    
    let tableName: String
    
    let fields: [String: Any]
    
    var consistency: Consistency

    var flags: Flags = .none

    public init(_ fields: [String: Any], into tableName: String, consistency: Consistency = .any) {
        self.fields = fields
        self.tableName = tableName
        self.consistency = consistency
    }
    
    public mutating func set(consistency: Consistency = .any, flags: Flags = .none) {
        self.flags = flags
        self.consistency = consistency
    }
    
    public func with(consistency: Consistency = .any, flags: Flags = .none) -> Insert {
        var new = self
        new.set(consistency: consistency, flags: flags)
        return self
    }
    
    public func pack() -> Data {
        var data = Data()
    
        let keys = packKeys(fields)
        let vals = packValues(fields)
        
        data.append(("INSERT INTO \(tableName) (\(keys)) VALUES(\(vals));").longStringData)
        data.append(consistency.rawValue.data)
        data.append(flags.rawValue.data)
        
        return data
    }
}
public struct Raw: Query {

    let query: String

    var consistency: Consistency

    var flags: Flags = .none

    init(query: String, consistency: Consistency = .one) {
        self.query = query
        self.consistency = consistency
    }

    public mutating func set(consistency: Consistency = .any, flags: Flags = .none) {
        self.flags = flags
        self.consistency = consistency
    }
    
    public func with(consistency: Consistency = .any, flags: Flags = .none) -> Raw {
        var new = self
        new.set(consistency: consistency, flags: flags)
        return self
    }

    public func pack() -> Data {
        var data = Data()
    
        data.append(query.longStringData)
        data.append(consistency.rawValue.data)
        data.append(flags.rawValue.data)
        
        return data
    }
}



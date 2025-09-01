//
//  ChartGrouping.swift
//  UIComponents
//
//  Created by 이택성 on 8/28/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

@frozen
public enum ChartGrouping: Int, CaseIterable {
    case daily = 1
    case weekly = 2
    case monthly = 3
}

public extension ChartGrouping {
    var string: String {
        let key = String(format: "label.chart.grouping.%d", self.rawValue)
        let localizedStringResource = LocalizedStringResource(stringLiteral: key)
        
        return String(localized: localizedStringResource)
    }
    
    /// 선택한 시간 그룹 기준에 따라 x축에 표시할 값의 개수 설정
    var xValueCount: Double {
        switch self {
        case .daily: 24
        case .weekly: 7
        case .monthly: 31
        }
    }
    
    /// x축 값의 단위 설정
    var xValueUnit: Calendar.Component {
        switch self {
        case .daily: .hour
        case .weekly: .day
        case .monthly: .day
        }
    }
    
    /// x축 간의 간격 값 설정
    var xVisibleDomain: Int {
        switch self {
        case .daily: 24 * 3600
        case .weekly: 7 * 24 * 3600
        case .monthly: 31 * 24 * 3600
        }
    }
    
    /// 차트 스크롤이 멈출 떄 정렬되는 시간 요소
    var xScrollAlignment: DateComponents {
        switch self {
            case .daily: DateComponents(minute: 0)
            case .weekly, .monthly: DateComponents(hour: 0, minute: 0)
        }
    }
    
    /// 현재 grouping 설정에 따라 그룹화 하기 위한 기준 날짜 계산
    func keyDate(_ date: Date) -> Date{
        let calendar = Calendar.autoupdatingCurrent
        return switch self {
            case .daily: calendar.startOfHour(for: date)
            case .weekly, .monthly: calendar.startOfDay(for: date)
        }
    }
    
    /// 주어진 날짜가 경계 날짜인지 확인
    func isAxisLimitMArk(_ date: Date) -> Bool {
        let calendar: Calendar = .current
        switch self {
        case .daily:
            let components = calendar.dateComponents([.hour], from: date)
            return (components.hour == 0)
        case .weekly:
            let components = calendar.dateComponents([.weekday], from: date)
            return (components.weekday == 2)
        case .monthly:
            let components = calendar.dateComponents([.month], from: date)
            return (components.day == 1)
        }
    }
    
    /// 주어진 날짜가 보여줘야 하는지 체크
    func isAxisMark(_ date: Date) -> Bool {
        let calendar: Calendar = .current
        switch self {
        case .daily:
            let components = calendar.dateComponents([.hour], from: date)
            return components.hour?.isMultiple(of: 6) ?? false
        case .weekly:
            return true
        case .monthly:
            let components = calendar.dateComponents([.weekday], from: date)
            return components.weekday == 2
        }
    }
    

    /// 주어진 날짜에 따라 page date 결정
    func pageDate(for date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return switch self {
            case .daily: calendar.startOfDay(for: date)
            case .weekly: calendar.startOfWeek(for: date)
            case .monthly: calendar.startOfMonth(for: date)
        }
    }
    
    /// 그룹화 값과 오프셋 고려해서 다음 페이지 날짜 계산
    func nextPageDate(for date: Date, offset: Int = 0) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let pageDate = pageDate(for: date)
        return switch self {
            case .daily: calendar.date(byAdding: .day, value: 1 * offset, to: pageDate)!
            case .weekly: calendar.date(byAdding: .day, value: 7 * offset, to: pageDate)!
            case .monthly: calendar.date(byAdding: .month, value: 1 * offset, to: pageDate)!
        }
    }
    
    func dateFormatString(page: ChartDataPage) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        let dateFrom = page.xScale.lowerBound
        let dateTo = page.xScale.upperBound
        
        switch self {
        case .daily:
            formatter.dateFormat = "dd MMM yyyy"
            return formatter.string(from: dateFrom)
        case .weekly:
            let componentsFrom = calendar.dateComponents([.day, .month, .year], from: dateFrom)
            let componentsTo = calendar.dateComponents([.day, .month, .year], from: dateTo)
            
            formatter.dateFormat = "dd"
            
            if componentsFrom.month != componentsTo.month {
                formatter.dateFormat = "dd MMM"
            }
            
            if componentsFrom.year != componentsTo.year {
                formatter.dateFormat = "dd MMM yyyy"
            }
            
            let dateFromString = formatter.string(from: dateFrom)
            
            formatter.dateFormat = "dd MMM yyyy"
            
            let dateToString = formatter.string(from: dateTo)
            
            return "\(dateFromString) - \(dateToString)"
        case .monthly:
            let componentsFrom = calendar.dateComponents([.day, .month, .year], from: dateFrom)
            let componentsTo = calendar.dateComponents([.day, .month, .year], from: dateTo)
            
            formatter.dateFormat = "MMM yyyy"
            
            if componentsFrom.month == componentsTo.month {
                return formatter.string(from: dateFrom)
            }
            
            formatter.dateFormat = "dd MMM"
            
            if componentsFrom.year != componentsTo.year {
                formatter.dateFormat = "dd MMM yyyy"
            }
            
            let dateFromString = formatter.string(from: dateFrom)
            
            formatter.dateFormat = "dd MMM yyyy"
            
            let dateToString = formatter.string(from: dateTo)
            
            return "\(dateFromString) - \(dateToString)"
        }
    }
}

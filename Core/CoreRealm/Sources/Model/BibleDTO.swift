//
//  BibleDTO.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import RealmSwift

public class BibleDTO: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var title: BibleTitle
    @Persisted var chapterTitle: String?
    @Persisted var chapter: Int
    @Persisted var section: Int
    @Persisted var sentence: String
    
    public convenience init(title: BibleTitle, 
                            chapterTitle: String? = nil,
                            chapter: Int,
                            section: Int,
                            sentence: String) {
        self.init()
        self.title = title
        self.chapterTitle = chapterTitle
        self.chapter = chapter
        self.section = section
        self.sentence = sentence
    }
    
    
    public enum BibleTitle: String, Equatable, CaseIterable, PersistableEnum {
        case genesis = "1-01창세기.txt"
        case exodus = "1-02출애굽기.txt"
        case leviticus = "1-03레위기.txt"
        case numbers = "1-04민수기.txt"
        case deuteronomy = "1-05신명기.txt"
        case joshua = "1-06여호수아.txt"
        case judges = "1-07사사기.txt"
        case ruth = "1-08룻기.txt"
        case samuel1 = "1-09사무엘상.txt"
        case samuel2 = "1-10사무엘하.txt"
        case kings1 = "1-11열왕기상.txt"
        case kings2 = "1-12열왕기하.txt"
        case chronicles1 = "1-13역대상.txt"
        case chronicles2 = "1-14역대하.txt"
        case ezra = "1-15에스라.txt"
        case nehemiah = "1-16느헤미야.txt"
        case esther = "1-17에스더.txt"
        case job = "1-18욥기.txt"
        case psalms = "1-19시편.txt"
        case proverbs = "1-20잠언.txt"
        case ecclesiasters = "1-21전도서.txt"
        case songOfSongs = "1-22아가.txt"
        case isaiah = "1-23이사야.txt"
        case jeremiah = "1-24예레미야.txt"
        case lementations = "1-25예레미야애가.txt"
        case ezekiel = "1-26에스겔.txt"
        case daniel = "1-27다니엘.txt"
        case hosea = "1-28호세아.txt"
        case joel = "1-29요엘.txt"
        case amos = "1-30아모스.txt"
        case obadiah = "1-31오바댜.txt"
        case jonah = "1-32요나.txt"
        case micah = "1-33미가.txt"
        case nahum = "1-34나훔.txt"
        case habakuk = "1-35하박국.txt"
        case zephaniah = "1-36스바냐.txt"
        case haggai = "1-37학개.txt"
        case zechariah = "1-38스가랴.txt"
        case malachi = "1-39말라기.txt"
        
        case matthew = "2-01마태복음.txt"
        case mark = "2-02마가복음.txt"
        case luke = "2-03누가복음.txt"
        case john = "2-04요한복음.txt"
        case acts = "2-05사도행전.txt"
        case romans = "2-06로마서.txt"
        case corinthians1 = "2-07고린도전서.txt"
        case corinthians2 = "2-08고린도후서.txt"
        case galatians = "2-09갈라디아서.txt"
        case ephesians = "2-10에베소서.txt"
        case philippians = "2-11빌립보서.txt"
        case colossians = "2-12골로새서.txt"
        case thessalonians1 = "2-13데살로니가전서.txt"
        case thessalonians2 = "2-14데살로니가후서.txt"
        case timothy1 = "2-15디모데전서.txt"
        case timothy2 = "2-16디모데후서.txt"
        case titus = "2-17디도서.txt"
        case philemon = "2-18빌레몬서.txt"
        case hebrews = "2-19히브리서.txt"
        case james = "2-20야고보서.txt"
        case peter1 = "2-21베드로전서.txt"
        case peter2 = "2-22베드로후서.txt"
        case john1 = "2-23요한일서.txt"
        case john2 = "2-24요한이서.txt"
        case john3 = "2-25요한삼서.txt"
        case jude = "2-26유다서.txt"
        case revelation = "2-27요한계시록.txt"
        
        mutating func next() {
            let allCases = type(of: self).allCases
            let currentIndex = allCases.firstIndex(of: self)!
            
            if self != .revelation {
                self = allCases[currentIndex + 1]
            }
        }
        mutating func before() {
            let allCases = type(of: self).allCases
            let currentIndex = allCases.firstIndex(of: self)!
            
            if self != .genesis {
                self = allCases[currentIndex - 1]
            }
        }
    }
    
}

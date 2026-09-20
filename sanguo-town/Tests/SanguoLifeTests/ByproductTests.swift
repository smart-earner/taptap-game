import Testing
import Foundation
@testable import SanguoLifeCore

@Test func lifeByproductRecoveryPreventsFoodDeadlock() throws {
    let (r,x)=try fixture();var s=x
    try LifeEngine.advance(&s,to:30*86400,rules:r)
    #expect(s.satisfaction==70)
    #expect(s.stock("home","meal")>0)
    #expect(s.ledger.consumed["fodder",default:0]>0)
    #expect(s.totalServed>35000)
    try s.validate(r)
}
@Test func lifeMulchIsAnActualLaborRecipeNotFreeDisposal() throws {
    let r=try LifeRules.load();let row=try #require(r.recipe("mulch"))
    #expect(row.work==30);#expect(row.inputs==["fodder":8]);#expect(row.outputs.isEmpty)
}

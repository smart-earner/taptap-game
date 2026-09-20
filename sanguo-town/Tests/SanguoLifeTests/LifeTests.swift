import Testing
import Foundation
@testable import SanguoLifeCore

@Test func lifeConfigurationLoads() throws {let r=try LifeRules.load();#expect(r.crops.count==3);#expect(r.heroes.count==6)}
@Test func lifeStartsWithSixteenRealPeople() throws {let r=try LifeRules.load();let s=try LifeEngine.newGame(wallUTC:0,rules:r);#expect(s.agents.count==16);try s.validate(r)}

func fixture() throws -> (LifeRules,LifeState) {let r=try LifeRules.load();return(r,try LifeEngine.newGame(wallUTC:0,rules:r))}
@Test func lifeFirstMealIsActuallyConsumed() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:1080,rules:r);#expect(s.totalServed==16);#expect(s.achievements==["first-meal"]);#expect(s.ledger.consumed["meal"]==16);#expect(s.satisfaction==70)}
@Test func lifeNoFreeMealAtStart() throws {let(_,s)=try fixture();#expect(s.totalServed==0);#expect(s.achievements.isEmpty)}
@Test func lifeHarvestIsNotMaturity() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:1800,rules:r);#expect(s.ledger.produced["paddy",default:0]==0);#expect(s.fields["field"]?.phase=="growing")}
@Test func lifeRiceEntersActualProcessingChain() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:7200,rules:r);#expect(s.ledger.produced["paddy",default:0]>=48);#expect(s.ledger.consumed["paddy",default:0]>=12);#expect(s.ledger.produced["grain",default:0]>=10);#expect(s.ledger.produced["meal",default:0]>=8);try s.validate(r)}
@Test func lifeNoDoubleCreditOnSameTimestamp() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:7200,rules:r);let before=s;try LifeEngine.advance(&s,to:7200,rules:r);#expect(s==before)}
@Test func lifeChunkingDoesNotAffectTasks() throws {let(r,x)=try fixture();var a=x,b=x;try LifeEngine.advance(&a,to:7200,rules:r);for t in stride(from:Int64(17),to:7200,by:17) {try LifeEngine.advance(&b,to:t,rules:r)};try LifeEngine.advance(&b,to:7200,rules:r);#expect(a==b)}
@Test func lifeSaveRoundTripResumesCargo() throws {let(r,x)=try fixture();var a=x;try LifeEngine.advance(&a,to:137,rules:r);var b=try JSONDecoder().decode(LifeState.self,from:JSONEncoder().encode(a));#expect(a==b);try LifeEngine.advance(&a,to:7200,rules:r);try LifeEngine.advance(&b,to:7200,rules:r);#expect(a==b)}
@Test func lifeTransportMovesRatherThanCopies() throws {
    let (r,x)=try fixture();var s=x
    try LifeEngine.advance(&s,to:50,rules:r)
    #expect(s.tasks.contains{$0.kind=="haul" && $0.cargo>0})
    try s.validate(r)
    let cargo=s.tasks.filter{$0.key=="grain"}.reduce(0){$0+$1.cargo}
    let wip=s.tasks.filter{$0.kind != "haul" && $0.inputsTaken}.reduce(0){$0+($1.inputs["grain"] ?? 0)}
    let actual=s.total("grain")+cargo+wip
    let expected=s.ledger.initial["grain",default:0]+s.ledger.produced["grain",default:0]-s.ledger.consumed["grain",default:0]
    #expect(actual==expected)
}
@Test func lifePopulationNeedsBuiltHousingAndMeals() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:21_600,rules:r);#expect(s.housing==20);#expect(s.population==20);#expect(s.constructionCount==1);#expect(s.treasury==460)}
@Test func lifeNoConstructionBeforeMaterialDelivery() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:120,rules:r);#expect(s.constructionCount==0);#expect(s.housing==16)}
@Test func lifeNightPreservesResidentsAndStopsNewProduction() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:2650,rules:r);#expect(s.isNight);#expect(s.agents.count==17);#expect(s.tasks.filter{$0.kind != "patrol" && $0.kind != "return"}.isEmpty);#expect(s.tasks.contains{$0.kind=="patrol"});#expect(s.agents.filter{$0.role != "patrol-night"}.allSatisfy{$0.site=="home"})}
@Test func lifeCropSwitchPreservesCurrentInvestment() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:400,rules:r);let old=s.fields["field"];try LifeEngine.changeCrop(&s,site:"field",crop:"millet",rules:r);#expect(s.fields["field"]?.crop=="rice");#expect(s.fields["field"]?.maturesAt==old?.maturesAt);#expect(s.fields["field"]?.nextCrop=="millet")}
@Test func lifeUnknownCropRejectedWithoutMutation() throws {let(r,x)=try fixture();var s=x;#expect(throws:LifeError.self){try LifeEngine.changeCrop(&s,site:"field",crop:"gold",rules:r)};#expect(s==x)}
@Test func lifeProjectionNeverChangesEconomy() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:100,rules:r);let before=s;for a in s.agents {for t in 0..<48 {_=LifeProjection.position(a,state:s,rules:r,at:Double(100+t))}};#expect(s==before)}
@Test func lifeLightUsesSavedTime() throws {let r=try LifeRules.load();#expect(LifeProjection.light(at:500,rules:r)==1);#expect(LifeProjection.light(at:2500,rules:r)==0.35);#expect(LifeProjection.light(at:2880+500,rules:r)==1)}
@Test func lifeFirstAchievementDoesNotRepeat() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advance(&s,to:21_600,rules:r);#expect(s.achievements.filter{$0=="first-meal"}.count==1)}
@Test func lifeFoodShortageFallsGradually() throws {let(r,x)=try fixture();var s=x;for site in s.stores.keys {for key in ["meal","grain","paddy"] {s.ledger.initial[key,default:0]-=s.stock(site,key);s.stores[site]![key]=0}};s.tasks=[];for i in s.agents.indices {s.agents[i].task=nil;s.agents[i].role="prefect"};for k in s.fields.keys {s.fields[k]!.task=nil};try LifeEngine.advance(&s,to:1080,rules:r);#expect(s.totalServed==0);#expect(s.satisfaction==62);#expect(s.population==16)}
@Test func lifeCorruptResourceStateRejected() throws {let(r,x)=try fixture();var s=x;s.stores["warehouse"]!["grain"] = -1;#expect(throws:LifeError.self){try s.validate(r)}}
@Test func lifeCargoReferencesAreValidated() throws {let(r,x)=try fixture();var s=x;s.agents[0].task=999;#expect(throws:LifeError.self){try s.validate(r)}}
@Test func lifeBackwardsTimeDoesNotRegress() throws {let(r,x)=try fixture();var s=x;try LifeEngine.advanceWall(&s,to:100,rules:r);let old=s;try LifeEngine.advanceWall(&s,to:50,rules:r);#expect(s==old)}
@Test func lifeThirtyDayLimitParameterIsExact() throws {let r=try LifeRules.load();#expect(r.clock.offlineLimit==30*86400)}
@Test func lifeHeroCataloguePreservesSixInitialProfiles() throws {let r=try LifeRules.load();#expect(r.heroes.first{$0.id=="zhaoyun"}?.attributes["valor"]==94);#expect(r.heroes.first{$0.id=="zhaoyun"}?.recruitSeconds.reduce(0,+)==72000)}
@Test func lifeUnownedHeroesHaveNoEffect() {#expect(LifeHeroEffects.value(hero:"liang",effect:"craftWork",base:100,owned:false,onDuty:true)==100)}
@Test func lifeTravellingHeroHasNoEffect() {#expect(LifeHeroEffects.value(hero:"lusu",effect:"importGoods",base:100,owned:true,onDuty:false)==100)}
@Test func lifeSixHeroEffectsAreExactAndScoped() {#expect(LifeHeroEffects.value(hero:"xunyu",effect:"satisfactionFall",base:8,owned:true,onDuty:true)==4);#expect(LifeHeroEffects.value(hero:"liang",effect:"craftWork",base:100,owned:true,onDuty:true)==88);#expect(LifeHeroEffects.value(hero:"liang",effect:"cropMaturity",base:1800,owned:true,onDuty:true)==1800);#expect(LifeHeroEffects.value(hero:"lusu",effect:"importGoods",base:101,owned:true,onDuty:true)==93);#expect(LifeHeroEffects.value(hero:"zhaoyun",effect:"wounded",base:11,owned:true,onDuty:true)==9);#expect(LifeHeroEffects.value(hero:"guanyu",effect:"trainingWork",base:100,owned:true,onDuty:true)==90);#expect(LifeHeroEffects.value(hero:"zhangfei",effect:"militaryCarry",base:8,owned:true,onDuty:true)==10);#expect(LifeHeroEffects.value(hero:"zhangfei",effect:"civilCarry",base:8,owned:true,onDuty:true)==8)}
@Test func lifeBasicWorkerAttributeIsNeutral() {#expect(LifeHeroEffects.baseWork(100,attribute:50)==100)}
struct BrokenLifeStore:LifePersistence {func save(_ state:LifeState) throws {throw LifeError.invalid("模拟磁盘故障")}}
@Test func lifeSaveFailureDoesNotPublishCandidate() async throws {let(r,x)=try fixture();let session=try LifeSession(state:x,rules:r,persistence:BrokenLifeStore());await #expect(throws:LifeError.self){try await session.advance(to:600)};let y=await session.snapshot();#expect(x==y)}
@Test func lifeStoreDoesNotResetCorruptFile() throws {let(r,s)=try fixture();let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)};let store=LifeSaveStore(url:folder.appendingPathComponent("city.json"));try store.save(s);#expect(try store.load(rules:r)==s);try Data("broken".utf8).write(to:store.url);#expect(throws:(any Error).self){try store.load(rules:r)};#expect(try Data(contentsOf:store.url)==Data("broken".utf8))}
@Test func lifeSavingKeepsThreeBackups() throws {let(r,x)=try fixture();var s=x;let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)};let store=LifeSaveStore(url:folder.appendingPathComponent("city.json"));for t in 0...4 {try LifeEngine.advance(&s,to:Int64(t*100),rules:r);try store.save(s)};for i in 1...3 {#expect(FileManager.default.fileExists(atPath:store.url.path+".bak\(i)"))}}

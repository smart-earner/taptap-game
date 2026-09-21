import Foundation

// Explicit preview profile; not a claim of full hero-town-0.8.0 conformance.
// Values: spec/hero-town-v0.8.json bootstrap and recipes.
extension LifeCatalog {
    func heroPreviewCatalog() -> LifeCatalog {
        var c=self
        for i in c.recipes.indices {
            switch c.recipes[i].id {
            case "cook_basic":
                c.recipes[i].input_mU=["grain":1000,"wood":250]
                c.recipes[i].output_mU=["meal":4000]
                c.recipes[i].prepare_s=30;c.recipes[i].passive_s=30;c.recipes[i].finish_s=10
            case "cook_meat":
                c.recipes[i].input_mU=["grain":1000,"meat":500,"wood":250]
                c.recipes[i].output_mU=["meal":4000]
                c.recipes[i].prepare_s=45;c.recipes[i].passive_s=45;c.recipes[i].finish_s=10
            default:break
            }
        }
        return c
    }
}
extension LifeRuntime {
    mutating func planHeroAdministration() {
        guard world.isHeroPreview,world.phase<1800,
              world.time>=world.counters["admin_lease",default:0],
              let a=world.agents[world.prefect],a.taskID==nil,
              !world.meals.contains(where:{!$0.closed && $0.expected.contains(a.id) && $0.served[a.id]==nil}) else{return}
        _=assign(kind:"administration",job:"clerk",subject:"hall",at:"hall",work:30,only:a.id)
    }
    mutating func setHeroPreference(_ id:String,_ job:String) throws {
        guard world.isHeroPreview,["cook","farmer","logger","porter","builder","flex"].contains(job),world.agents[id] != nil else{throw LifeError.invalid("无效的武将分工")}
        world.agents[id]!.job=job
        world.record("preference","\(world.agents[id]!.name)的劳动偏好已调整；当前任务继续完成，紧急保供优先。")
    }
}

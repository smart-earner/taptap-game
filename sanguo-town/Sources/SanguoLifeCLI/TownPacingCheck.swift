import Foundation
import SanguoLife

enum TownPacingCheck {
    static func run() throws {
        var passed=0
        func check(_ condition:Bool,_ id:String,_ message:String)throws {
            guard condition else{throw LifeError.invalid("\(id) FAILED: \(message)")}
            passed+=1;print("PASS \(id) \(message)")
        }
        func fixture(_ built:Set<String>=[])throws->LifeRuntime {
            let source=try LifeRuntime(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:92)
            var world=source.world
            var repair=world.projects["repair"]!
            repair.completedWork=repair.totalWork;repair.phase=4;repair.completed=true;repair.allocatedWork=0;repair.stageStarted=false
            world.projects=[repair.id:repair]
            world.tasks=[:]
            for id in world.agents.keys {world.agents[id]!.taskID=nil}
            for id in world.lots.keys {world.lots[id]!.reserved=0}
            for id in world.storages.keys {world.storages[id]!.incoming=0}
            for plotID in built {
                guard let index=world.heroTown!.city.plots.firstIndex(where:{$0.id==plotID}) else{continue}
                let kind=world.heroTown!.city.plots[index].kind
                world.heroTown!.city.plots[index].level=1
                world.heroTown!.city.plots[index].service=10000
                world.heroTown!.city.plots[index].capacity=["house":5,"farm":4,"granary":256,"workshop":1][kind,default:1]
                world.buildings[kind,default:0]+=1
            }
            if built.contains("house-2") {world.gacha!.houseLevels=[1,1]}
            return try .init(catalog:.bundled(),world:world)
        }
        func nextProject(_ built:Set<String>=[])throws->LifeProject? {
            var runtime=try fixture(built);try runtime.advance(to:30)
            return runtime.world.projects.values.first{$0.id != "repair" && !$0.completed}
        }

        try check(LifeTownPacingContract.defaultPresentationSpeed==2,"PC01","desktop presentation defaults to 2x")
        try check(LifeTownPacingContract.formalResourceWorkRateBonusBP==1500
                  && LifeTownPacingContract.resourceJobs==["farmer","logger","miner"],
                  "PC02","formal farm, wood and mine work receive the exact 15 percent pacing bonus")
        try check(try nextProject()?.targetPlotID=="house-2","PC03","the first capacity project is visible housing")
        let farm=try nextProject(["house-2"])
        try check(farm?.targetPlotID=="farm-2" && farm?.cash==0 && farm?.materials.values.allSatisfy{$0>0}==true,
                  "PC04","second farm is built with real materials before abstract civic upgrades")
        try check(try nextProject(["house-2","farm-2"])?.targetPlotID=="granary-2",
                  "PC05","second granary follows the farm as visible storage capacity")
        try check(try nextProject(["house-2","farm-2","granary-2"])?.targetPlotID=="workshop-1",
                  "PC06","workshop completes the early visible production foundation")
        print("Town pacing runtime: \(passed)/6 checks passed.")
    }
}

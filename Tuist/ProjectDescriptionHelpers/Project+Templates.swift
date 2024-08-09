import ProjectDescription

public extension Project {
    static func makeModule(
      name: String,
      organizationName: String = "leetaek",
      packages: [Package] = [],
      targets: [Target],
      schemes: [Scheme] = [],
      settings: Settings? = .settings(
        base: SettingsDictionary()
            .automaticCodeSigning(devTeam: "H4MSW7FUBB")
            .otherLinkerFlags(["-all_load -Objc"])
    ),
      additionalFiles: [FileElement] = [],
      resourceSynthesizers: [ResourceSynthesizer] = []
    ) -> Project {
      
      return Project(
        name: name,
        organizationName: organizationName,
        packages: packages,
        settings: settings,
        targets: targets,
        schemes: schemes,
        additionalFiles: additionalFiles,
        resourceSynthesizers: resourceSynthesizers
      )
    }
    
}

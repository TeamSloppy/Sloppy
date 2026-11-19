import Testing
@testable import sloppy

@Test func studioBuildRequiresAnExactMachineAliasInTheSourceMessage() {
    #expect(CoreService.studioBuildAliasIsExplicit("$home_machine", in: "собери Studio на $home_machine"))
    #expect(CoreService.studioBuildAliasIsExplicit("$home_machine", in: "Build Studio on $home_machine, please."))
    #expect(!CoreService.studioBuildAliasIsExplicit("$home_machine", in: "build on $home_machine_other"))
    #expect(!CoreService.studioBuildAliasIsExplicit("$home_machine", in: "build on \\$home_machine"))
    #expect(!CoreService.studioBuildAliasIsExplicit("$home_machine", in: "build on prefix$home_machine"))
    #expect(!CoreService.studioBuildAliasIsExplicit("$home_machine", in: "build locally"))
}

@Test func studioBuildIsAnExplicitCoordinatorHandoff() {
    #expect(LongChatCoordinatorPolicy.isExecutionHandoff("long_chat.build_studio"))
    #expect(LongChatCoordinatorPolicy.managementTools.contains("long_chat.build_studio"))
    #expect(!LongChatCoordinatorPolicy.isExecutionHandoff("runtime.exec"))
}

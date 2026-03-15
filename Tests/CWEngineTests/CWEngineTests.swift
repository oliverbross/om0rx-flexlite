import CW
import Testing

@Test
func storesAndDequeuesCWText() async {
    let engine = CWEngine()
    await engine.send(text: "CQ TEST", block: 1)

    #expect(await engine.dequeue() == "CQ TEST")
}

@Test
func storesMacros() async {
    let engine = CWEngine()
    let macro = CWMacro(title: "TU", text: "TU 73")
    await engine.saveMacro(macro)

    #expect(await engine.allMacros().contains(macro))
}

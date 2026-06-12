evidence-binding: n2-empty-result-feedback 11d0368621bd
RED: test_emptyRecognitionResult_setsOverlayMessage — compile error: value of type MainViewModel has no member overlayMessage and handleRecognitionResult is inaccessible (all 3 EmptyResultFeedbackTests cases fail to compile before fix)
GREEN: 3/3 EmptyResultFeedbackTests pass — overlayMessage set to "未识别到内容" for empty and whitespace-only inputs, remains nil for non-empty input
Added @Published var overlayMessage: String? and internal func handleRecognitionResult(_ text: String) to MainViewModel.swift; added EmptyResultFeedbackTests class with 3 test methods to MainViewModelTests.swift.

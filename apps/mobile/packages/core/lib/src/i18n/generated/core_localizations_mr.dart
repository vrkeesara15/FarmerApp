// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class CoreLocalizationsMr extends CoreLocalizations {
  CoreLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get appNameAgent => 'मित्र';

  @override
  String get appNameFarmer => 'किसान';

  @override
  String get splashTagline => 'तुमच्या शेतासाठी विश्वासू सल्ला';

  @override
  String get actionContinue => 'पुढे जा';

  @override
  String get actionBack => 'मागे';

  @override
  String get actionNext => 'पुढील';

  @override
  String get actionRetry => 'पुन्हा प्रयत्न करा';

  @override
  String get actionCancel => 'रद्द करा';

  @override
  String get actionDone => 'झाले';

  @override
  String get actionSkip => 'वगळा';

  @override
  String get actionClose => 'बंद करा';

  @override
  String get loading => 'लोड होत आहे';

  @override
  String get languagePickerTitle => 'तुमची भाषा निवडा';

  @override
  String get languagePickerSubtitle => 'ऐकण्यासाठी स्पीकर दाबा';

  @override
  String get languagePlayAudio => 'ऐका';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageKannada => 'ಕನ್ನಡ';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageEnglishName => 'इंग्रजी';

  @override
  String get languageTeluguName => 'तेलुगू';

  @override
  String get languageKannadaName => 'कन्नड';

  @override
  String get languageHindiName => 'हिंदी';

  @override
  String get languageMarathiName => 'मराठी';

  @override
  String get phoneLoginTitle => 'तुमचा मोबाईल नंबर टाका';

  @override
  String get phoneLabel => 'मोबाईल नंबर';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'आम्ही SMS ने 6 अंकी OTP पाठवू';

  @override
  String get phoneInvalid => 'योग्य 10 अंकी मोबाईल नंबर टाका';

  @override
  String get phoneSendOtp => 'OTP पाठवा';

  @override
  String get otpTitle => 'OTP टाका';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone वर पाठवला';
  }

  @override
  String get otpLabel => '6 अंकी OTP';

  @override
  String get otpResend => 'OTP पुन्हा पाठवा';

  @override
  String otpResendIn(int seconds) {
    return '$seconds सेकंदांत पुन्हा पाठवा';
  }

  @override
  String get otpInvalid => 'OTP चुकीचा आहे. पुन्हा प्रयत्न करा.';

  @override
  String get otpVerify => 'तपासा';

  @override
  String otpDigitLabel(int index) {
    return '6 पैकी $indexवा अंक';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count प्रयत्न शिल्लक';
  }

  @override
  String otpLocked(int minutes) {
    return 'खूप वेळा चुकीचा OTP. $minutes मिनिटांनी पुन्हा प्रयत्न करा.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'खूप वेळा OTP मागितला. $minutes मिनिटांनी पुन्हा प्रयत्न करा.';
  }

  @override
  String get otpExpired => 'हा OTP संपला आहे. नवीन मागा.';

  @override
  String get phoneNotFound =>
      'हा नंबर नोंदणीकृत नाही. तुम्हाला जोडण्यासाठी मॅनेजरला सांगा.';

  @override
  String get networkError =>
      'कनेक्शन नाही. नेटवर्क तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get consentTitle => 'तुमचे लोकेशन आणि डेटा';

  @override
  String get consentPoint1 => 'आम्ही तुमचे लोकेशन आणि भेटीचे फोटो घेतो.';

  @override
  String get consentPoint2 => 'लोकेशन फक्त ड्युटीवर असताना घेतले जाते.';

  @override
  String get consentPoint3 =>
      'याचा वापर प्रवास भत्ता आणि भेट क्रेडिटसाठी होतो.';

  @override
  String get consentPoint4 =>
      'तुमचे मॅनेजर आणि मालक ते पाहू शकतात. शेतकरी नाही.';

  @override
  String get consentAgree => 'मी सहमत आहे';

  @override
  String get consentPolicyLink => 'पूर्ण धोरण वाचा';

  @override
  String get consentDataCardTitle => 'पीक सल्ल्यासाठी माझा डेटा वापरा';

  @override
  String get consentDataCardBody =>
      'तुम्हाला मदत करण्यासाठी आम्ही तुमच्या पिकाचे फोटो आणि शेताची माहिती पाहतो.';

  @override
  String get consentRequired => 'आवश्यक';

  @override
  String get consentOffersCardTitle => 'मला ऑफर आणि टिप्स पाठवा';

  @override
  String get consentOffersCardBody => 'उत्पादने आणि शेतीच्या टिप्सबद्दल संदेश.';

  @override
  String get consentOptional => 'ऐच्छिक';

  @override
  String get consentReadAloud => 'वाचून ऐकवा';

  @override
  String get dutyOn => 'ड्युटीवर';

  @override
  String get dutyOff => 'ड्युटीवर नाही';

  @override
  String get dutyGoOn => 'ड्युटी सुरू करा';

  @override
  String get dutyGoOff => 'ड्युटी संपवा';

  @override
  String dutyElapsed(String duration) {
    return '$duration पासून ड्युटीवर';
  }

  @override
  String get dutyLocationNote => 'लोकेशन फक्त ड्युटीवर असताना चालू असते';

  @override
  String get syncSynced => 'सिंक झाले';

  @override
  String syncPending(int count) {
    return '$count बाकी';
  }

  @override
  String get syncFailed => 'सिंक अयशस्वी';

  @override
  String get offlineBanner =>
      'तुम्ही ऑफलाइन आहात. तुमचे काम सेव्ह आहे आणि नंतर सिंक होईल.';

  @override
  String get visitVerified => 'पडताळलेली';

  @override
  String get visitPartial => 'अंशतः';

  @override
  String get visitUnverified => 'न पडताळलेली';

  @override
  String visitScore(int score) {
    return '100 पैकी $score गुण';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes मिनिटे';
  }

  @override
  String get visitPurposeAdvisory => 'सल्ला';

  @override
  String get visitPurposeScouting => 'शेत पाहणी';

  @override
  String get visitPurposeDemo => 'डेमो';

  @override
  String get visitPurposeCollection => 'वसुली';

  @override
  String get visitPurposeSale => 'विक्री';

  @override
  String get visitPurposeMeeting => 'बैठक';

  @override
  String get proofGeofence => 'शेताच्या हद्दीत';

  @override
  String get proofGeofenceMissing => 'तुम्ही शेताच्या हद्दीबाहेर होता';

  @override
  String get proofPhoto => 'फोटो घेतला';

  @override
  String get proofPhotoMissing => 'भेटीदरम्यान फोटो घेतला नाही';

  @override
  String get proofFarmerConfirmed => 'शेतकऱ्याने पुष्टी केली';

  @override
  String get proofFarmerConfirmedMissing =>
      'शेतकऱ्याने भेटीची पुष्टी केली नाही';

  @override
  String get proofDuration => 'शेतावर किमान वेळ पूर्ण';

  @override
  String get proofDurationMissing => 'भेट 10 मिनिटांपेक्षा कमी होती';

  @override
  String get proofDone => 'झाले';

  @override
  String get proofMissing => 'नाही';

  @override
  String get cameraHoldSteady => 'स्थिर धरा';

  @override
  String get cameraGoodLight => 'चांगला प्रकाश';

  @override
  String get cameraFillFrame => 'फ्रेम भरा';

  @override
  String get cameraLeafFrame => 'पान फ्रेमच्या आत ठेवा';

  @override
  String get confidenceHigh => 'उच्च विश्वास';

  @override
  String get confidenceMedium => 'मध्यम विश्वास';

  @override
  String get confidenceLow => 'तात्पुरते';

  @override
  String get diagnosisSymptomsTitle => 'ही लक्षणे तपासा';

  @override
  String get diagnosisProvisionalNote => 'आमचे तज्ज्ञ 24 तासांत पुष्टी करतील';

  @override
  String get diagnosisProblem => 'समस्या';

  @override
  String get treatmentOrganic => 'सेंद्रिय';

  @override
  String get treatmentChemical => 'रासायनिक';

  @override
  String get treatmentActiveIngredient => 'सक्रिय घटक';

  @override
  String get treatmentDosePerAcre => 'प्रति एकर';

  @override
  String get treatmentDosePerTank => 'प्रति 15 ली टाकी';

  @override
  String treatmentSafetyInterval(int days) {
    return 'काढणीपूर्वी $days दिवस थांबा';
  }

  @override
  String get treatmentPpeGloves => 'हातमोजे';

  @override
  String get treatmentPpeMask => 'मास्क';

  @override
  String get treatmentPpeGoggles => 'चष्मा';

  @override
  String get treatmentPpeTitle => 'घाला';

  @override
  String get ownBrand => 'स्वतःचा ब्रँड';

  @override
  String get productAdd => 'जोडा';

  @override
  String get productAdded => 'जोडले';

  @override
  String productStockAtStore(int count, String store) {
    return '$store येथे $count स्टॉकमध्ये';
  }

  @override
  String get productOutOfStock => 'स्टॉक नाही';

  @override
  String get productPack => 'पॅक';

  @override
  String cartItems(int count) {
    return '$count वस्तू';
  }

  @override
  String get cartTotal => 'एकूण';

  @override
  String get cartCheckout => 'पैसे भरा';

  @override
  String get paymentMethodTitle => 'तुम्ही कसे पैसे भराल?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'स्कॅन करून आता पैसे भरा';

  @override
  String get paymentLink => 'पेमेंट लिंक';

  @override
  String get paymentLinkHint => 'SMS किंवा WhatsApp ने पाठवा';

  @override
  String get paymentCash => 'रोख';

  @override
  String get paymentCashHint => 'रोख घ्या आणि पावती द्या';

  @override
  String get paymentCredit => 'उधारी';

  @override
  String get paymentCreditHint => 'शेतकऱ्याच्या खात्यात जोडा';

  @override
  String get upiWaiting => 'पेमेंटची वाट पाहत आहोत';

  @override
  String get upiPaid => 'पेमेंट मिळाले';

  @override
  String get upiFailed => 'पेमेंट अयशस्वी';

  @override
  String upiExpiresIn(String time) {
    return '$time मध्ये संपेल';
  }

  @override
  String get upiAmount => 'रक्कम';

  @override
  String get upiScanHint => 'शेतकऱ्याला कोणत्याही UPI ॲपने स्कॅन करायला सांगा';

  @override
  String get upiRetry => 'नवीन QR दाखवा';

  @override
  String get khataBalance => 'थकबाकी';

  @override
  String khataDueDate(String date) {
    return '$date पर्यंत देय';
  }

  @override
  String get khataDebit => 'दिले';

  @override
  String get khataCredit => 'मिळाले';

  @override
  String get khataNoEntries => 'अजून नोंदी नाहीत';

  @override
  String get khataPayNow => 'आता पैसे भरा';

  @override
  String get khataCollect => 'वसूल करा';

  @override
  String get emptyDefaultTitle => 'अजून येथे काही नाही';

  @override
  String get emptyDefaultHelp => 'जोडल्यानंतर वस्तू येथे दिसतील.';

  @override
  String get errorTitle => 'काहीतरी चूक झाली';

  @override
  String get errorHelp => 'कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get ratingTitle => 'तुमच्या भेटीला रेटिंग द्या';

  @override
  String get rating1 => 'खूप वाईट';

  @override
  String get rating2 => 'वाईट';

  @override
  String get rating3 => 'ठीक';

  @override
  String get rating4 => 'चांगले';

  @override
  String get rating5 => 'खूप चांगले';

  @override
  String stepperStepOf(int current, int total) {
    return '$total पैकी पायरी $current';
  }

  @override
  String farmerLastVisit(String date) {
    return 'शेवटची भेट $date';
  }

  @override
  String get farmerNoVisit => 'अजून भेट नाही';

  @override
  String farmerBalanceDue(String amount) {
    return 'थकबाकी $amount';
  }

  @override
  String get farmerVillage => 'गाव';

  @override
  String get statTrendUp => 'वाढ';

  @override
  String get statTrendDown => 'घट';

  @override
  String get statTrendFlat => 'बदल नाही';

  @override
  String get stageSowing => 'पेरणी';

  @override
  String get stageVegetative => 'वाढ';

  @override
  String get stageFlowering => 'फुलोरा';

  @override
  String get stageFruiting => 'फळधारणा';

  @override
  String get stageHarvest => 'काढणी';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeSunlight => 'ऊन';

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get skeletonLoading => 'मजकूर लोड होत आहे';
}

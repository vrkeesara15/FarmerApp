// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class CoreLocalizationsTe extends CoreLocalizations {
  CoreLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appNameAgent => 'మిత్ర';

  @override
  String get appNameFarmer => 'కిసాన్';

  @override
  String get splashTagline => 'మీ పొలానికి నమ్మకమైన సలహా';

  @override
  String get actionContinue => 'కొనసాగించు';

  @override
  String get actionBack => 'వెనుకకు';

  @override
  String get actionNext => 'తరువాత';

  @override
  String get actionRetry => 'మళ్ళీ ప్రయత్నించండి';

  @override
  String get actionCancel => 'రద్దు';

  @override
  String get actionDone => 'పూర్తి';

  @override
  String get actionSkip => 'దాటవేయి';

  @override
  String get actionClose => 'మూసివేయి';

  @override
  String get loading => 'లోడ్ అవుతోంది';

  @override
  String get languagePickerTitle => 'మీ భాషను ఎంచుకోండి';

  @override
  String get languagePickerSubtitle => 'వినడానికి స్పీకర్‌ను నొక్కండి';

  @override
  String get languagePlayAudio => 'వినండి';

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
  String get languageEnglishName => 'ఇంగ్లీష్';

  @override
  String get languageTeluguName => 'తెలుగు';

  @override
  String get languageKannadaName => 'కన్నడ';

  @override
  String get languageHindiName => 'హిందీ';

  @override
  String get languageMarathiName => 'మరాఠీ';

  @override
  String get phoneLoginTitle => 'మీ మొబైల్ నంబర్ నమోదు చేయండి';

  @override
  String get phoneLabel => 'మొబైల్ నంబర్';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'మేము SMS ద్వారా 6 అంకెల OTP పంపుతాము';

  @override
  String get phoneInvalid => 'సరైన 10 అంకెల మొబైల్ నంబర్ నమోదు చేయండి';

  @override
  String get phoneSendOtp => 'OTP పంపండి';

  @override
  String get otpTitle => 'OTP నమోదు చేయండి';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone కు పంపబడింది';
  }

  @override
  String get otpLabel => '6 అంకెల OTP';

  @override
  String get otpResend => 'OTP మళ్ళీ పంపండి';

  @override
  String otpResendIn(int seconds) {
    return '$seconds సెకన్లలో మళ్ళీ పంపండి';
  }

  @override
  String get otpInvalid => 'OTP తప్పు. మళ్ళీ ప్రయత్నించండి.';

  @override
  String get otpVerify => 'ధృవీకరించు';

  @override
  String otpDigitLabel(int index) {
    return '6లో $indexవ అంకె';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count ప్రయత్నాలు మిగిలాయి';
  }

  @override
  String otpLocked(int minutes) {
    return 'చాలా తప్పు ప్రయత్నాలు. $minutes నిమిషాల తర్వాత మళ్ళీ ప్రయత్నించండి.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'చాలా సార్లు OTP అడిగారు. $minutes నిమిషాల తర్వాత మళ్ళీ ప్రయత్నించండి.';
  }

  @override
  String get otpExpired => 'ఈ OTP గడువు ముగిసింది. కొత్తది అడగండి.';

  @override
  String get phoneNotFound =>
      'ఈ నంబర్ నమోదు కాలేదు. మిమ్మల్ని జోడించమని మీ మేనేజర్‌ను అడగండి.';

  @override
  String get networkError =>
      'కనెక్షన్ లేదు. మీ నెట్‌వర్క్ తనిఖీ చేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get consentTitle => 'మీ లొకేషన్ మరియు డేటా';

  @override
  String get consentPoint1 =>
      'మేము మీ లొకేషన్ మరియు సందర్శన ఫోటోలను సేకరిస్తాము.';

  @override
  String get consentPoint2 =>
      'మీరు డ్యూటీలో ఉన్నప్పుడు మాత్రమే లొకేషన్ సేకరిస్తాము.';

  @override
  String get consentPoint3 =>
      'ఇది ప్రయాణ భత్యం మరియు సందర్శన క్రెడిట్ కోసం ఉపయోగిస్తాము.';

  @override
  String get consentPoint4 =>
      'మీ మేనేజర్ మరియు యజమాని చూడగలరు. రైతులు చూడలేరు.';

  @override
  String get consentAgree => 'నేను అంగీకరిస్తున్నాను';

  @override
  String get consentPolicyLink => 'పూర్తి విధానం చదవండి';

  @override
  String get consentDataCardTitle => 'పంట సలహా ఇవ్వడానికి నా డేటాను వాడండి';

  @override
  String get consentDataCardBody =>
      'మీకు సహాయం చేయడానికి మీ పంట ఫోటోలు, పొలం వివరాలు చూస్తాము.';

  @override
  String get consentRequired => 'తప్పనిసరి';

  @override
  String get consentOffersCardTitle => 'నాకు ఆఫర్లు మరియు సలహాలు పంపండి';

  @override
  String get consentOffersCardBody =>
      'ఉత్పత్తులు మరియు వ్యవసాయ సలహాల గురించి సందేశాలు.';

  @override
  String get consentOptional => 'ఐచ్ఛికం';

  @override
  String get consentReadAloud => 'చదివి వినిపించు';

  @override
  String get dutyOn => 'డ్యూటీలో ఉన్నారు';

  @override
  String get dutyOff => 'డ్యూటీలో లేరు';

  @override
  String get dutyGoOn => 'డ్యూటీ ప్రారంభించు';

  @override
  String get dutyGoOff => 'డ్యూటీ ముగించు';

  @override
  String dutyElapsed(String duration) {
    return '$duration నుండి డ్యూటీలో';
  }

  @override
  String get dutyLocationNote =>
      'మీరు డ్యూటీలో ఉన్నప్పుడు మాత్రమే లొకేషన్ ఆన్‌లో ఉంటుంది';

  @override
  String get syncSynced => 'సింక్ అయింది';

  @override
  String syncPending(int count) {
    return '$count పెండింగ్';
  }

  @override
  String get syncFailed => 'సింక్ విఫలమైంది';

  @override
  String get offlineBanner =>
      'మీరు ఆఫ్‌లైన్‌లో ఉన్నారు. మీ పని సేవ్ అయింది, తర్వాత సింక్ అవుతుంది.';

  @override
  String get visitVerified => 'ధృవీకరించబడింది';

  @override
  String get visitPartial => 'పాక్షికం';

  @override
  String get visitUnverified => 'ధృవీకరించలేదు';

  @override
  String visitScore(int score) {
    return '100కు $score స్కోరు';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes నిమి';
  }

  @override
  String get visitPurposeAdvisory => 'సలహా';

  @override
  String get visitPurposeScouting => 'పొలం పరిశీలన';

  @override
  String get visitPurposeDemo => 'డెమో';

  @override
  String get visitPurposeCollection => 'వసూలు';

  @override
  String get visitPurposeSale => 'అమ్మకం';

  @override
  String get visitPurposeMeeting => 'సమావేశం';

  @override
  String get proofGeofence => 'పొలం హద్దుల లోపల';

  @override
  String get proofGeofenceMissing => 'మీరు పొలం హద్దుల బయట ఉన్నారు';

  @override
  String get proofPhoto => 'ఫోటో తీశారు';

  @override
  String get proofPhotoMissing => 'సందర్శనలో ఫోటో తీయలేదు';

  @override
  String get proofFarmerConfirmed => 'రైతు ధృవీకరించారు';

  @override
  String get proofFarmerConfirmedMissing => 'రైతు సందర్శనను ధృవీకరించలేదు';

  @override
  String get proofDuration => 'పొలంలో కనీస సమయం పూర్తయింది';

  @override
  String get proofDurationMissing => 'సందర్శన 10 నిమిషాల కంటే తక్కువ';

  @override
  String get proofDone => 'పూర్తి';

  @override
  String get proofMissing => 'లేదు';

  @override
  String get cameraHoldSteady => 'కదలకుండా పట్టుకోండి';

  @override
  String get cameraGoodLight => 'మంచి వెలుతురు';

  @override
  String get cameraFillFrame => 'ఫ్రేమ్ నింపండి';

  @override
  String get cameraLeafFrame => 'ఆకును ఫ్రేమ్ లోపల ఉంచండి';

  @override
  String get confidenceHigh => 'అధిక నమ్మకం';

  @override
  String get confidenceMedium => 'మధ్యస్థ నమ్మకం';

  @override
  String get confidenceLow => 'తాత్కాలికం';

  @override
  String get diagnosisSymptomsTitle => 'ఈ లక్షణాలు చూడండి';

  @override
  String get diagnosisProvisionalNote => 'మా నిపుణులు 24 గంటల్లో ధృవీకరిస్తారు';

  @override
  String get diagnosisProblem => 'సమస్య';

  @override
  String get treatmentOrganic => 'సేంద్రియ';

  @override
  String get treatmentChemical => 'రసాయన';

  @override
  String get treatmentActiveIngredient => 'క్రియాశీల పదార్థం';

  @override
  String get treatmentDosePerAcre => 'ఎకరానికి';

  @override
  String get treatmentDosePerTank => '15 లీ ట్యాంకుకు';

  @override
  String treatmentSafetyInterval(int days) {
    return 'కోతకు ముందు $days రోజులు ఆగండి';
  }

  @override
  String get treatmentPpeGloves => 'చేతి తొడుగులు';

  @override
  String get treatmentPpeMask => 'మాస్క్';

  @override
  String get treatmentPpeGoggles => 'కళ్ళజోడు';

  @override
  String get treatmentPpeTitle => 'ధరించండి';

  @override
  String get ownBrand => 'సొంత బ్రాండ్';

  @override
  String get productAdd => 'జోడించు';

  @override
  String get productAdded => 'జోడించారు';

  @override
  String productStockAtStore(int count, String store) {
    return '$storeలో $count స్టాక్ ఉంది';
  }

  @override
  String get productOutOfStock => 'స్టాక్ లేదు';

  @override
  String get productPack => 'ప్యాక్';

  @override
  String cartItems(int count) {
    return '$count వస్తువులు';
  }

  @override
  String get cartTotal => 'మొత్తం';

  @override
  String get cartCheckout => 'చెల్లించు';

  @override
  String get paymentMethodTitle => 'ఎలా చెల్లిస్తారు?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'స్కాన్ చేసి ఇప్పుడే చెల్లించండి';

  @override
  String get paymentLink => 'చెల్లింపు లింక్';

  @override
  String get paymentLinkHint => 'SMS లేదా WhatsApp ద్వారా పంపండి';

  @override
  String get paymentCash => 'నగదు';

  @override
  String get paymentCashHint => 'నగదు తీసుకుని రసీదు ఇవ్వండి';

  @override
  String get paymentCredit => 'అరువు';

  @override
  String get paymentCreditHint => 'రైతు ఖాతాలో వేయండి';

  @override
  String get upiWaiting => 'చెల్లింపు కోసం వేచి ఉన్నాము';

  @override
  String get upiPaid => 'చెల్లింపు అందింది';

  @override
  String get upiFailed => 'చెల్లింపు విఫలమైంది';

  @override
  String upiExpiresIn(String time) {
    return '$timeలో గడువు ముగుస్తుంది';
  }

  @override
  String get upiAmount => 'మొత్తం';

  @override
  String get upiScanHint => 'ఏదైనా UPI యాప్‌తో స్కాన్ చేయమని రైతును అడగండి';

  @override
  String get upiRetry => 'కొత్త QR చూపించు';

  @override
  String get khataBalance => 'బాకీ మొత్తం';

  @override
  String khataDueDate(String date) {
    return '$date లోపు చెల్లించాలి';
  }

  @override
  String get khataDebit => 'ఇచ్చింది';

  @override
  String get khataCredit => 'వచ్చింది';

  @override
  String get khataNoEntries => 'ఇంకా ఎంట్రీలు లేవు';

  @override
  String get khataPayNow => 'ఇప్పుడే చెల్లించు';

  @override
  String get khataCollect => 'వసూలు చేయి';

  @override
  String get emptyDefaultTitle => 'ఇంకా ఏమీ లేదు';

  @override
  String get emptyDefaultHelp => 'మీరు జోడించాక ఇక్కడ కనిపిస్తాయి.';

  @override
  String get errorTitle => 'ఏదో తప్పు జరిగింది';

  @override
  String get errorHelp => 'మీ కనెక్షన్ తనిఖీ చేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get ratingTitle => 'మీ సందర్శనకు రేటింగ్ ఇవ్వండి';

  @override
  String get rating1 => 'చాలా చెడు';

  @override
  String get rating2 => 'చెడు';

  @override
  String get rating3 => 'పర్వాలేదు';

  @override
  String get rating4 => 'బాగుంది';

  @override
  String get rating5 => 'చాలా బాగుంది';

  @override
  String stepperStepOf(int current, int total) {
    return '$totalలో $currentవ దశ';
  }

  @override
  String farmerLastVisit(String date) {
    return 'చివరి సందర్శన $date';
  }

  @override
  String get farmerNoVisit => 'ఇంకా సందర్శన లేదు';

  @override
  String farmerBalanceDue(String amount) {
    return 'బాకీ $amount';
  }

  @override
  String get farmerVillage => 'గ్రామం';

  @override
  String get statTrendUp => 'పెరిగింది';

  @override
  String get statTrendDown => 'తగ్గింది';

  @override
  String get statTrendFlat => 'మార్పు లేదు';

  @override
  String get stageSowing => 'విత్తడం';

  @override
  String get stageVegetative => 'పెరుగుదల';

  @override
  String get stageFlowering => 'పూత';

  @override
  String get stageFruiting => 'కాత';

  @override
  String get stageHarvest => 'కోత';

  @override
  String get settingsTheme => 'థీమ్';

  @override
  String get themeLight => 'లైట్';

  @override
  String get themeSunlight => 'ఎండ';

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get settingsLanguage => 'భాష';

  @override
  String get skeletonLoading => 'కంటెంట్ లోడ్ అవుతోంది';
}

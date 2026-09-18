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
  String get syncSyncing => 'సింక్ అవుతోంది…';

  @override
  String get syncDetailsTitle => 'సింక్ వివరాలు';

  @override
  String get syncNow => 'ఇప్పుడే సింక్ చేయండి';

  @override
  String syncLastSync(String time) {
    return 'చివరి సింక్ $time';
  }

  @override
  String get syncNeverSynced => 'ఇంకా సింక్ కాలేదు';

  @override
  String get syncAllDone => 'అన్నీ సింక్ అయ్యాయి';

  @override
  String get syncAllDoneHelp =>
      'ఆఫ్‌లైన్‌లో సేవ్ చేసిన కొత్త రైతులు, పొలాలు, ఫోటోలు సర్వర్‌కు చేరే వరకు ఇక్కడ కనిపిస్తాయి.';

  @override
  String syncPendingSection(int count) {
    return 'సింక్ కోసం వేచి ఉన్నవి ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'శ్రద్ధ అవసరం ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'ఫోటో అప్‌లోడ్ కోసం వేచి ఉంది';

  @override
  String syncPhotoUploads(int count) {
    return 'అప్‌లోడ్ అవుతున్న ఫోటోలు: $count';
  }

  @override
  String get syncTransportError =>
      'సర్వర్‌ను చేరుకోలేకపోయాం. అదే మళ్లీ ప్రయత్నిస్తుంది.';

  @override
  String syncNextAttempt(String time) {
    return 'తదుపరి ప్రయత్నం $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'కొత్త';

  @override
  String get syncActionUpdate => 'సవరించిన';

  @override
  String get syncActionDelete => 'తొలగించిన';

  @override
  String get syncEntityFarmer => 'రైతు';

  @override
  String get syncEntityFarm => 'పొలం';

  @override
  String get syncEntityCropPlot => 'పంట ప్లాట్';

  @override
  String get syncEntityConsent => 'సమ్మతి';

  @override
  String get syncEntityOther => 'అంశం';

  @override
  String syncSavedAt(String time) {
    return 'సేవ్ చేసినది $time';
  }

  @override
  String get syncRejectedDefault =>
      'సర్వర్ ఈ అంశాన్ని అంగీకరించలేదు. సవరించి మళ్లీ ప్రయత్నించండి.';

  @override
  String get syncRetryAll => 'అన్నీ మళ్లీ ప్రయత్నించండి';

  @override
  String get syncDiscard => 'వదిలేయండి';

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
  String get photoReviewHeading => 'మీ ఫోటోను చూడండి';

  @override
  String photoReviewTitle(int index, int total) {
    return 'ఫోటో $index / $total';
  }

  @override
  String get photoQualityOk => 'మంచి ఫోటో';

  @override
  String get photoQualityBlurry => 'మసకగా ఉంది';

  @override
  String get photoQualityDark => 'చాలా చీకటిగా ఉంది';

  @override
  String get photoQualityChecking => 'ఫోటోను చూస్తున్నాం';

  @override
  String get photoTipBlurry =>
      'ఫోన్‌ను స్థిరంగా పట్టుకోండి, ఆకుపై నొక్కి ఫోకస్ చేసి మళ్ళీ తీయండి';

  @override
  String get photoTipDark =>
      'మంచి వెలుతురులోకి వెళ్ళి, నీడ నుంచి బయటకు వచ్చి మళ్ళీ తీయండి';

  @override
  String get photoTipOk => 'ఫోటో బాగుంది';

  @override
  String get photoRetake => 'మళ్ళీ తీయండి';

  @override
  String get photoUse => 'ఈ ఫోటో వాడండి';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

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

  @override
  String get farmersTitle => 'రైతులు';

  @override
  String get farmersSearchHint => 'పేరు, ఫోన్ లేదా గ్రామం వెతకండి';

  @override
  String get farmersAddFarmer => 'రైతును చేర్చండి';

  @override
  String get farmersEmptyTitle => 'ఇంకా రైతులు లేరు';

  @override
  String get farmersEmptyHelp =>
      'సందర్శనలు, ఆర్డర్లు మొదలుపెట్టడానికి మొదటి రైతును చేర్చండి.';

  @override
  String get farmersNoResults => 'మీ వెతుకులాటకు సరిపోయే రైతులు లేరు';

  @override
  String get farmersFilterVillage => 'గ్రామం';

  @override
  String get farmersFilterCrop => 'పంట';

  @override
  String get farmersFilterAll => 'అన్నీ';

  @override
  String farmersCount(int count) {
    return '$count రైతులు';
  }

  @override
  String get farmerPendingSync => 'ఆన్‌లైన్ అయినప్పుడు సింక్ అవుతుంది';

  @override
  String get farmerPhoneUnverified => 'ఫోన్ ధృవీకరించలేదు';

  @override
  String get farmerRejected => 'శ్రద్ధ అవసరం';

  @override
  String get regTitle => 'రైతును చేర్చండి';

  @override
  String get regStepBasics => 'రైతు వివరాలు';

  @override
  String get regStepBoundary => 'పొలం సరిహద్దు';

  @override
  String get regStepCrops => 'పంటలు';

  @override
  String get regStepConsent => 'అనుమతి';

  @override
  String get regStepReview => 'సమీక్షించి సేవ్ చేయండి';

  @override
  String get regResumeDraft => 'మీరు ఆపిన చోటు నుండి కొనసాగుతోంది';

  @override
  String get regDiscardDraft => 'డ్రాఫ్ట్ తీసివేయండి';

  @override
  String get regFixIssues => 'కొనసాగడానికి గుర్తించిన ఫీల్డ్‌లను సరిచేయండి';

  @override
  String get regNameLabel => 'రైతు పేరు';

  @override
  String get regNameHint => 'గుర్తింపు కార్డులో ఉన్నట్లు';

  @override
  String get regPhoneLabel => 'రైతు మొబైల్ నంబర్';

  @override
  String get regPhoneHelper => 'రైతుకు OTP పంపబడుతుంది';

  @override
  String get regSendOtpToFarmer => 'రైతుకు OTP పంపండి';

  @override
  String get regOtpSent => 'రైతుకు OTP పంపాం. వారి నుండి కోడ్ అడగండి.';

  @override
  String get regPhoneVerified => 'ఫోన్ ధృవీకరించబడింది';

  @override
  String get regVerifyLater => 'తర్వాత ధృవీకరించండి';

  @override
  String get regVerifyLaterNote =>
      'సిగ్నల్ లేదా? ఇప్పుడు సేవ్ చేసి, రైతు ప్రొఫైల్ నుండి ఫోన్ ధృవీకరించండి.';

  @override
  String get regVerifyLaterChosen => 'తర్వాత ధృవీకరించబడుతుంది';

  @override
  String get regDuplicatePhone => 'ఈ నంబర్‌తో రైతు ఇప్పటికే ఉన్నారు';

  @override
  String get regDuplicateOpen => 'ఉన్న రైతును తెరవండి';

  @override
  String get regVillageLabel => 'గ్రామం';

  @override
  String get regVillageHint => 'గ్రామం ఎంచుకోండి';

  @override
  String get regVillageTyped => 'గ్రామం పేరు';

  @override
  String get regVillageNoneSynced =>
      'మొదటి సింక్ తర్వాత గ్రామాలు లోడ్ అవుతాయి. ప్రస్తుతానికి గ్రామం పేరు టైప్ చేయండి.';

  @override
  String get regLandmarkLabel => 'గుర్తు';

  @override
  String get regLandmarkHint => 'గుడి, బడి దగ్గర…';

  @override
  String get regLanguageLabel => 'రైతు భాష';

  @override
  String get regOwnershipLabel => 'భూమి';

  @override
  String get regBoundaryWalk => 'చుట్టూ నడవండి';

  @override
  String get regBoundaryTap => 'మూలలు నొక్కండి';

  @override
  String get regStartWalk => 'నడక మొదలుపెట్టండి';

  @override
  String get regStopWalk => 'ఆపండి';

  @override
  String get regClosePolygon => 'సరిహద్దు మూసివేయండి';

  @override
  String get regUndoPoint => 'పాయింట్ వెనక్కి';

  @override
  String get regClearBoundary => 'తుడిచివేయండి';

  @override
  String regPointsCount(int count) {
    return '$count పాయింట్లు';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS ఖచ్చితత్వం ±$metres మీ';
  }

  @override
  String get regAccuracyWaiting => 'GPS కోసం వేచి ఉంది…';

  @override
  String get regLocationOff => 'సరిహద్దు నడవడానికి లొకేషన్ ఆన్ చేయండి';

  @override
  String get regLocationDenied => 'సరిహద్దు నడవడానికి లొకేషన్ అనుమతి అవసరం';

  @override
  String get regTapHint => 'మ్యాప్‌లో పొలం నాలుగు మూలలను నొక్కండి';

  @override
  String get regWalkHint =>
      'పొలం అంచు వెంట నడవండి. మీరు నడుస్తుండగా పాయింట్లు చేరుతాయి.';

  @override
  String regComputedArea(String acres) {
    return 'కొలిచిన విస్తీర్ణం $acres ఎకరాలు';
  }

  @override
  String get regAreaLabel => 'విస్తీర్ణం ఎకరాల్లో';

  @override
  String get regAreaHint => 'రైతు చెప్పినట్లు';

  @override
  String get regUseMeasured => 'కొలిచినది వాడండి';

  @override
  String get regAreaWarning =>
      'నమోదు చేసిన విస్తీర్ణం కొలిచిన విస్తీర్ణం కంటే 30% కంటే ఎక్కువ తేడాగా ఉంది. సేవ్ చేసే ముందు సరిచూడండి.';

  @override
  String get regBoundaryInvalid =>
      'సరిహద్దు తనను తాను దాటుతోంది. చివరి పాయింట్లు వెనక్కి తీసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get regFarmNameLabel => 'పొలం పేరు (ఐచ్ఛికం)';

  @override
  String get regFarmNameHint => 'ఇంటి పొలం';

  @override
  String get regSoilLabel => 'నేల రకం';

  @override
  String get regIrrigationLabel => 'నీటిపారుదల';

  @override
  String get regFarmPhoto => 'పొలం ఫోటో (ఐచ్ఛికం)';

  @override
  String get regTakePhoto => 'ఫోటో తీయండి';

  @override
  String get regPhotoAdded => 'ఫోటో చేర్చబడింది';

  @override
  String get regPhotoRemove => 'తీసివేయండి';

  @override
  String regFarmPhotosCount(int count) {
    return '$count ఫోటోలు';
  }

  @override
  String get regCropsHelp =>
      'ఈ సీజన్‌లో ఈ పొలంలో పెరుగుతున్న ప్రతి పంటను చేర్చండి.';

  @override
  String get regAddCrop => 'పంట చేర్చండి';

  @override
  String get regCropLabel => 'పంట';

  @override
  String get regVarietyLabel => 'రకం';

  @override
  String get regVarietyHint => 'ఉదా. MTU-1010';

  @override
  String get regSowingDateLabel => 'విత్తిన తేదీ';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'సీజన్: $season';
  }

  @override
  String get regPlotAreaLabel => 'విస్తీర్ణం (ఎకరాలు, ఐచ్ఛికం)';

  @override
  String get regRemoveCrop => 'పంట తీసివేయండి';

  @override
  String regPlotTitle(int index) {
    return 'పంట $index';
  }

  @override
  String get regAddFarm => 'మరో పొలం చేర్చండి';

  @override
  String regFarmsCount(int count) {
    return '$count పొలాలు';
  }

  @override
  String regFarmIndex(int index) {
    return 'పొలం $index';
  }

  @override
  String get regConsentIntro => 'దీన్ని రైతుకు వారి భాషలో చదివి వినిపించండి.';

  @override
  String get regConsentNotice =>
      'పంట సలహా ఇవ్వడానికి, సందర్శన రికార్డులు ఉంచడానికి మీ పేరు, ఫోన్, గ్రామం, పొలం వివరాలను మేము భద్రపరుస్తాం. ఎప్పుడైనా ఆపమని మమ్మల్ని అడగవచ్చు.';

  @override
  String get regConsentMarketingNotice =>
      'మీ అనుమతితో SMS లేదా WhatsApp ద్వారా ఆఫర్లు, వ్యవసాయ చిట్కాలు కూడా పంపుతాం.';

  @override
  String get regConsentGiven => 'రైతు అంగీకరిస్తున్నారు';

  @override
  String get regReviewFarmer => 'రైతు';

  @override
  String get regReviewFarms => 'పొలాలు, పంటలు';

  @override
  String get regReviewConsent => 'అనుమతి';

  @override
  String get regReviewSyncNote =>
      'ఇప్పుడు ఈ ఫోన్‌లో సేవ్ అయింది; నెట్‌వర్క్ వచ్చాక సర్వర్‌కు పంపబడుతుంది.';

  @override
  String get regSave => 'రైతును సేవ్ చేయండి';

  @override
  String get regSaveFarm => 'పొలం సేవ్ చేయండి';

  @override
  String get regEdit => 'సవరించండి';

  @override
  String get regSaved => 'రైతు సేవ్ అయ్యారు';

  @override
  String get regIssueName => 'రైతు పేరు నమోదు చేయండి';

  @override
  String get regIssuePhoneUnverified =>
      'ఫోన్ ధృవీకరించండి లేదా తర్వాత ధృవీకరించండి ఎంచుకోండి';

  @override
  String get regIssueVillage => 'గ్రామం ఎంచుకోండి';

  @override
  String get regIssueLanguage => 'రైతు భాషను ఎంచుకోండి';

  @override
  String get regIssueBoundary => 'సరిహద్దుకు కనీసం 3 పాయింట్లు గుర్తించండి';

  @override
  String get regIssueArea => 'విస్తీర్ణం ఎకరాల్లో నమోదు చేయండి';

  @override
  String get regIssueCrop => 'కనీసం ఒక పంట చేర్చండి';

  @override
  String get regIssueSowingDate => 'ప్రతి పంటకు విత్తిన తేదీ నమోదు చేయండి';

  @override
  String get regIssueConsent => 'నమోదుకు డేటా అనుమతి తప్పనిసరి';

  @override
  String get soilBlack => 'నల్ల నేల';

  @override
  String get soilRed => 'ఎర్ర నేల';

  @override
  String get soilSandy => 'ఇసుక నేల';

  @override
  String get soilLoamy => 'లోమ్ నేల';

  @override
  String get soilClay => 'బంక నేల';

  @override
  String get soilAlluvial => 'ఒండ్రు నేల';

  @override
  String get soilLaterite => 'లేటరైట్ నేల';

  @override
  String get irrigationRainfed => 'వర్షాధారం';

  @override
  String get irrigationBorewell => 'బోరుబావి';

  @override
  String get irrigationCanal => 'కాలువ';

  @override
  String get irrigationTank => 'చెరువు';

  @override
  String get irrigationOpenWell => 'బావి';

  @override
  String get irrigationDrip => 'డ్రిప్';

  @override
  String get irrigationSprinkler => 'స్ప్రింక్లర్';

  @override
  String get ownershipOwn => 'సొంతం';

  @override
  String get ownershipLeased => 'కౌలు';

  @override
  String get seasonKharif => 'ఖరీఫ్';

  @override
  String get seasonRabi => 'రబీ';

  @override
  String get seasonZaid => 'జైద్ (వేసవి)';

  @override
  String get profileTabOverview => 'అవలోకనం';

  @override
  String get profileTabVisits => 'సందర్శనలు';

  @override
  String get profileTabDiagnoses => 'రోగ నిర్ధారణలు';

  @override
  String get profileTabOrders => 'ఆర్డర్లు';

  @override
  String get profileTabKhata => 'ఖాతా';

  @override
  String get profileStartVisit => 'సందర్శన మొదలు';

  @override
  String get profileScout => 'పంట పరిశీలన';

  @override
  String get profileNewOrder => 'కొత్త ఆర్డర్';

  @override
  String get profileCollect => 'వసూలు';

  @override
  String get profileComingSoon => 'తర్వాతి అప్‌డేట్‌లో వస్తుంది';

  @override
  String get profileVisitsEmpty => 'ఇంకా సందర్శనలు లేవు';

  @override
  String get profileDiagnosesEmpty => 'ఇంకా రోగ నిర్ధారణలు లేవు';

  @override
  String get profileOrdersEmpty => 'ఇంకా ఆర్డర్లు లేవు';

  @override
  String get profileKhataEmpty => 'ఇంకా ఖాతా నమోదులు లేవు';

  @override
  String get profilePhone => 'ఫోన్';

  @override
  String get profileLandmark => 'గుర్తు';

  @override
  String get profileLanguage => 'భాష';

  @override
  String get profileOwnership => 'భూమి';

  @override
  String get profileFarms => 'పొలాలు';

  @override
  String profileAcres(String acres) {
    return '$acres ఎకరాలు';
  }

  @override
  String get profileAddFarm => 'పొలం చేర్చండి';

  @override
  String get profileEditFarm => 'పొలం సవరించండి';

  @override
  String profileFarmPlots(int count) {
    return '$count పంటలు';
  }

  @override
  String get profileNoFarms => 'ఇంకా పొలాలు లేవు';

  @override
  String get profileDuplicateTitle => 'నకిలీ — విలీనం చేయాలా?';

  @override
  String get profileDuplicateBody =>
      'ఈ నంబర్‌తో సర్వర్‌లో ఇప్పటికే రైతు ఉన్నారు. ఉన్న రికార్డు తెరిచి వివరాలను విలీనం చేయండి.';

  @override
  String get profileRejectedTitle => 'సింక్ తిరస్కరించబడింది';

  @override
  String get profileRejectedHelp =>
      'సరిచేసి మళ్లీ ప్రయత్నించడానికి సింక్ వివరాలు తెరవండి.';

  @override
  String get profileNotFound => 'రైతు కనబడలేదు';

  @override
  String get profileVerifyPhone => 'ఫోన్ ధృవీకరించండి';

  @override
  String get consentGiven => 'ఇచ్చారు';

  @override
  String get consentNotGiven => 'ఇవ్వలేదు';

  @override
  String get farmEditTitle => 'పొలం సవరించండి';

  @override
  String get farmAddTitle => 'పొలం చేర్చండి';

  @override
  String get mapNoBoundary => 'ఇంకా సరిహద్దు లేదు';

  @override
  String get mapAttribution => '© OpenStreetMap సహకారులు';

  @override
  String get mapCurrentPosition => 'మీ స్థానం';

  @override
  String mapCorner(int index) {
    return 'మూల $index';
  }

  @override
  String get mapFarmBoundary => 'పొలం సరిహద్దు';
}

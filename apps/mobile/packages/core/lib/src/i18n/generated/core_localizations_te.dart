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

  @override
  String get dutyNotificationTitle => 'డ్యూటీలో ఉన్నారు — లొకేషన్ ఆన్';

  @override
  String get dutyChannelName => 'డ్యూటీ';

  @override
  String get dutyAlertsChannelName => 'డ్యూటీ హెచ్చరికలు';

  @override
  String get dutyPromptTitle => 'ఇంకా డ్యూటీలో ఉన్నారా?';

  @override
  String dutyPromptBody(String time) {
    return '$timeకి ముగుస్తుంది';
  }

  @override
  String get dutyEndedTitle => 'డ్యూటీ ముగిసింది';

  @override
  String dutyAutoEndedBody(String time) {
    return 'మీ రోజు $timeకి ఆటోమేటిక్‌గా ముగిసింది.';
  }

  @override
  String get dutyServerEndedBody =>
      'సర్వర్ మీ డ్యూటీని ముగించింది (నిష్క్రియత లేదా రోజు ముగింపు).';

  @override
  String dutyAutoEndAt(String time) {
    return '$timeకి ఆటోమేటిక్‌గా ముగుస్తుంది';
  }

  @override
  String get dutyBlockedPolicy =>
      'డ్యూటీలోకి వెళ్లడానికి లొకేషన్ విధానాన్ని అంగీకరించండి';

  @override
  String get dutyReviewPolicy => 'విధానం చూడండి';

  @override
  String dutyPointsPending(int count) {
    return '$count పాయింట్లు అప్‌లోడ్ కోసం వేచి ఉన్నాయి';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'మీరు ఇప్పటికే మరో పరికరంలో డ్యూటీలో ఉన్నారు. ఇది ఆఫ్‌లోనే ఉంటుంది.';

  @override
  String get dutyNoticePolicy =>
      'డ్యూటీలోకి వెళ్లే ముందు ప్రస్తుత లొకేషన్ విధానాన్ని అంగీకరించండి.';

  @override
  String get dutyNoticeLocationUnavailable =>
      'మీ లొకేషన్ పొందలేకపోయాం. లొకేషన్ ఆన్ చేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get integrityBanner =>
      'కొన్ని పరికర తనిఖీలు సమస్యలను నివేదించాయి; సందర్శనలు సమీక్షించబడవచ్చు.';

  @override
  String get disclosureIntro =>
      'ప్రారంభించే ముందు, మిత్ర ఏమి నమోదు చేస్తుంది, ఎందుకు అనేది ఇక్కడ ఉంది.';

  @override
  String disclosureVersion(String version) {
    return 'విధాన సంస్కరణ $version';
  }

  @override
  String get disclosureUpdated =>
      'లొకేషన్ విధానం మారింది. దయచేసి కొత్త సంస్కరణను చదివి అంగీకరించండి.';

  @override
  String get policySheetTitle => 'లొకేషన్ విధానం';

  @override
  String get locationPolicyText =>
      'మిత్ర లొకేషన్ విధానం (సంస్కరణ 2026-09-v1)\n\n1. మేము ఏమి సేకరిస్తాము. మీరు డ్యూటీలో ఉన్నప్పుడు, మిత్ర మీ లొకేషన్ (అక్షాంశం, రేఖాంశం, ఖచ్చితత్వం, వేగం, దిశ), సమయం, బ్యాటరీ స్థాయి మరియు ప్రాథమిక పరికర తనిఖీలను (మాక్ లొకేషన్, రూట్ చేసిన పరికరం, గడియారం తేడా) నమోదు చేస్తుంది. సందర్శనల సమయంలో మీరు తీసే ఫోటోలు, గమనికలు, రైతు ధృవీకరణలను కూడా నమోదు చేస్తుంది.\n\n2. డ్యూటీలో ఉన్నప్పుడు మాత్రమే. మీరు డ్యూటీ ఆన్ చేసిన తర్వాతే లొకేషన్ నమోదు అవుతుంది; డ్యూటీ ఆఫ్ చేసిన క్షణం, సంస్థ నిర్ణయించిన సమయానికి రోజు ముగిసినప్పుడు (డిఫాల్ట్ 20:00) లేదా ఇంటి వద్ద 60 నిమిషాలు నిష్క్రియంగా ఉన్నప్పుడు ఆగిపోతుంది. డ్యూటీ ఆఫ్‌లో ఉన్నప్పుడు ఏమీ నమోదు కాదు; లొకేషన్ ఆన్‌లో ఉన్నంతసేపు నోటిఫికేషన్ ఎప్పుడూ కనిపిస్తుంది.\n\n3. ఎందుకు సేకరిస్తాము. మీ ట్రాక్ నుండి మీ ప్రయాణ భత్యం కోసం కిలోమీటర్లు లెక్కించబడతాయి; సందర్శన వద్ద మీ లొకేషన్ ఆ సందర్శనకు క్రెడిట్ ఇస్తుంది. ట్రాక్ లేకపోతే ఆటోమేటిక్ ప్రయాణ భత్యం లేదు, ధృవీకరించిన సందర్శన లేదు.\n\n4. ఎవరు చూడగలరు. మీ క్లస్టర్ హెడ్, డైరెక్టర్లు మరియు మీ సంస్థ యజమాని వారి ప్రాంతానికి మీ ట్రాక్, సందర్శనలను చూడగలరు; ఆడిటర్లు ఫ్లాగ్ చేసిన సందర్శనలను సమీక్షించగలరు. స్టోర్ మేనేజర్లు, రైతులు మీ లొకేషన్‌ను ఎప్పుడూ చూడరు. ముడి పాయింట్లు 180 రోజులు ఉంచి, ఆ తర్వాత రోజువారీ మొత్తాలుగా కుదించబడతాయి.';

  @override
  String get permissionsTitle => 'మిత్రకు కావలసిన అనుమతులు';

  @override
  String get permissionsIntro =>
      'మిత్ర వీటిని ఒక్కొక్కటిగా అడుగుతుంది. తర్వాత సెట్టింగ్స్‌లో మార్చుకోవచ్చు.';

  @override
  String get permLocationTitle => 'లొకేషన్';

  @override
  String get permLocationBody =>
      'డ్యూటీలో మీ ట్రాక్ నమోదు చేయడానికి, మీరు పొలం వద్ద ఉన్నారో లేదో చూడడానికి.';

  @override
  String get permBackgroundTitle => 'లొకేషన్ ఎల్లప్పుడూ';

  @override
  String get permBackgroundBody =>
      'స్క్రీన్ ఆఫ్‌లో ఉన్నా ట్రాకింగ్ కొనసాగడానికి \"ఎల్లప్పుడూ అనుమతించు\" ఎంచుకోండి. అయినా ఇది డ్యూటీలో ఉన్నప్పుడు మాత్రమే పనిచేస్తుంది.';

  @override
  String get permCameraTitle => 'కెమెరా';

  @override
  String get permCameraBody => 'యాప్ లోపల తీసే పొలం, సందర్శన ఫోటోల కోసం.';

  @override
  String get permNotificationsTitle => 'నోటిఫికేషన్లు';

  @override
  String get permNotificationsBody =>
      'డ్యూటీ నోటీసు చూపడానికి, డ్యూటీ ముగిసే ముందు గుర్తు చేయడానికి.';

  @override
  String get permGranted => 'అనుమతించారు';

  @override
  String get permDenied => 'అనుమతించలేదు';

  @override
  String get permOpenSettings => 'సెట్టింగ్స్ తెరవండి';

  @override
  String get permAllow => 'అనుమతించు';

  @override
  String get registeredTitle => 'పరికరం నమోదైంది';

  @override
  String get registeredBody =>
      'మీరు సిద్ధం. రోజు ప్రారంభించడానికి హోమ్ నుండి డ్యూటీలోకి వెళ్లండి.';

  @override
  String get registeredStart => 'హోమ్‌కు వెళ్లండి';

  @override
  String get homeTitle => 'హోమ్';

  @override
  String get homeTodayStats => 'ఈ రోజు';

  @override
  String get statVisitsVerified => 'ధృవీకరించిన సందర్శనలు';

  @override
  String get statFarmersAdded => 'చేర్చిన రైతులు';

  @override
  String get statCollections => 'వసూళ్లు';

  @override
  String get homeNextUp => 'తర్వాత';

  @override
  String get homeNextUpEmpty => 'ఇంకా బీట్ ప్లాన్ లేదు';

  @override
  String get homeNextUpEmptyHelp =>
      'మీ క్లస్టర్ హెడ్ గ్రామాలను కేటాయిస్తారు. అప్పటివరకు రైతులను చేర్చండి, సందర్శనలు ప్రారంభించండి.';

  @override
  String get homeQuickActions => 'త్వరిత చర్యలు';

  @override
  String get actionStartVisit => 'సందర్శన ప్రారంభించు';

  @override
  String get actionScoutCrop => 'పంట పరిశీలన';

  @override
  String get actionCollectPayment => 'చెల్లింపు వసూలు';

  @override
  String get comingSoon => 'త్వరలో వస్తుంది';

  @override
  String get navHome => 'హోమ్';

  @override
  String get navFarmers => 'రైతులు';

  @override
  String get navVisits => 'సందర్శనలు';

  @override
  String get navOrders => 'ఆర్డర్లు';

  @override
  String get navMe => 'నేను';

  @override
  String get myDayTitle => 'నా రోజు';

  @override
  String myDayKm(String km) {
    return 'ఈ రోజు $km కి.మీ';
  }

  @override
  String get myDayEmpty => 'ఈ రోజు ఇంకా డ్యూటీ లేదు';

  @override
  String get myDayEmptyHelp =>
      'హోమ్ నుండి డ్యూటీలోకి వెళ్లండి; మీ ట్రాక్, కి.మీ ఇక్కడ కనిపిస్తాయి.';

  @override
  String myDaySession(String start, String end) {
    return 'డ్యూటీ $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return '$start నుండి డ్యూటీ';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending పెండింగ్ · $accepted ఆమోదించారు';
  }

  @override
  String get myDayGapsTitle => 'గ్యాప్‌లు మరియు కారణాలు';

  @override
  String get myDayGapsHelp => 'గ్యాప్ కారణాలు తదుపరి అప్‌డేట్‌తో వస్తాయి.';

  @override
  String get myDayEndReasonManual => 'మీరు ముగించారు';

  @override
  String get myDayEndReasonAutoTime => 'రోజు ముగింపులో ముగిసింది';

  @override
  String get myDayEndReasonAutoIdle => 'నిష్క్రియత తర్వాత ముగిసింది';

  @override
  String get myDayEndReasonForced => 'మేనేజర్ ముగించారు';

  @override
  String get myDayEndReasonRejected => 'నమోదు కాలేదు';

  @override
  String get syncEntityDutySession => 'డ్యూటీ సెషన్';

  @override
  String get syncEntityLocationBatch => 'లొకేషన్ పాయింట్లు';

  @override
  String get syncEntityPolicyAcceptance => 'విధాన అంగీకారం';

  @override
  String get visitsTitle => 'సందర్శనలు';

  @override
  String get visitsTabToday => 'ఈరోజు';

  @override
  String get visitsTabWeek => 'ఈ వారం';

  @override
  String get visitsFilterAll => 'అన్నీ';

  @override
  String get visitsEmptyTitle => 'ఇంకా సందర్శనలు లేవు';

  @override
  String get visitsEmptyHelp =>
      'రైతు ప్రొఫైల్ నుండి లేదా కింది బటన్‌తో సందర్శన ప్రారంభించండి.';

  @override
  String get visitStatusOpen => 'కొనసాగుతోంది';

  @override
  String get visitCardPending => 'ఆన్‌లైన్ అయినప్పుడు సింక్ అవుతుంది';

  @override
  String get visitCardFailed => 'శ్రద్ధ అవసరం';

  @override
  String get visitChooseFarmer => 'రైతును ఎంచుకోండి';

  @override
  String get visitFarmLabel => 'పొలం';

  @override
  String get visitFarmNoBoundary => 'ఈ పొలానికి సరిహద్దు నమోదు కాలేదు';

  @override
  String get visitPurposeLabel => 'ఉద్దేశ్యం';

  @override
  String get visitOffDutyTitle => 'ముందుగా డ్యూటీలోకి వెళ్లండి';

  @override
  String get visitOffDutyBody =>
      'సందర్శనలు మీరు డ్యూటీలో ఉన్నప్పుడు మాత్రమే నమోదవుతాయి. హోమ్ నుండి డ్యూటీ ఆన్ చేసి తిరిగి రండి.';

  @override
  String get visitGoHome => 'హోమ్‌కు వెళ్లండి';

  @override
  String get visitLocating => 'మీ స్థానం తెలుసుకుంటున్నాం…';

  @override
  String get visitNoFix =>
      'మీ స్థానం దొరకలేదు. ఆరుబయటకు వెళ్లి మళ్లీ ప్రయత్నించండి.';

  @override
  String get visitRefreshLocation => 'స్థానం మళ్లీ తనిఖీ చేయండి';

  @override
  String visitAccuracy(int metres) {
    return 'ఖచ్చితత్వం ±$metres మీ';
  }

  @override
  String get visitInsideGeofence => 'మీరు పొలం జియోఫెన్స్ లోపల ఉన్నారు';

  @override
  String get visitAtMeetingPoint => 'మీరు గ్రామ సమావేశ స్థలంలో ఉన్నారు';

  @override
  String visitOutsideFarm(int distance, int radius) {
    return 'పొలం సరిహద్దు నుండి $distance మీ దూరంలో; జియోఫెన్స్ $radius మీ.';
  }

  @override
  String visitOutsideMeeting(int distance, int radius) {
    return 'సమావేశ స్థలం నుండి $distance మీ దూరంలో; అనుమతించిన పరిధి $radius మీ.';
  }

  @override
  String get visitNoTarget =>
      'ఈ పొలానికి సరిహద్దు లేదు, గ్రామానికి సమావేశ స్థలం లేదు. ఓవర్‌రైడ్ నోట్‌తో చెక్ ఇన్ చేయండి.';

  @override
  String get visitRequestOverride => 'ఓవర్‌రైడ్ కోరండి';

  @override
  String get visitOverrideNoteLabel =>
      'మీరు ఇక్కడి నుండి ఎందుకు చెక్ ఇన్ చేస్తున్నారు?';

  @override
  String get visitOverrideNoteHint => 'ఉదా. రైతును మార్కెట్‌లో కలిశాను';

  @override
  String get visitOverrideNoteRequired => 'ఓవర్‌రైడ్ కోరడానికి నోట్ రాయండి';

  @override
  String get visitOverrideHelp =>
      'మీ క్లస్టర్ హెడ్ ఓవర్‌రైడ్‌ను సమీక్షిస్తారు. ఆమోదిస్తేనే సందర్శనకు జియోఫెన్స్ క్రెడిట్ వస్తుంది.';

  @override
  String get visitCheckIn => 'చెక్ ఇన్';

  @override
  String get visitCheckInOverride => 'ఓవర్‌రైడ్‌తో చెక్ ఇన్';

  @override
  String get visitInProgress => 'సందర్శన కొనసాగుతోంది';

  @override
  String get visitTimerLabel => 'సందర్శన సమయం';

  @override
  String visitMinDuration(int minutes) {
    return 'కనీసం $minutes నిమి';
  }

  @override
  String visitDurationNeeds(int minutes, int minimum) {
    return '$minimum నిమిలో $minutes నిమి';
  }

  @override
  String visitUnderMinimum(int minutes) {
    return 'కనీసం $minutes నిమి కంటే తక్కువ. సందర్శన ఫ్లాగ్ చేయబడుతుంది, తిరస్కరించబడదు.';
  }

  @override
  String get visitPhotos => 'ఫోటోలు';

  @override
  String get visitTakePhoto => 'ఫోటో తీయండి';

  @override
  String visitPhotoCount(int count) {
    return '$count ఫోటోలు';
  }

  @override
  String get visitPhotosHelp =>
      'యాప్ కెమెరా మాత్రమే. పొలంలో కనీసం ఒక ఫోటో తీయండి.';

  @override
  String get visitNotesLabel => 'నోట్స్';

  @override
  String get visitNotesHint => 'మీరు ఏమి గమనించారు లేదా సలహా ఇచ్చారు?';

  @override
  String get visitVoiceInputSoon =>
      'వాయిస్ ఇన్‌పుట్ తర్వాతి అప్‌డేట్‌లో వస్తుంది';

  @override
  String get visitCropStageLabel => 'పంట దశ';

  @override
  String get cropStageSown => 'విత్తినది';

  @override
  String get cropStageMaturity => 'పక్వత';

  @override
  String get cropStageHarvested => 'కోత పూర్తి';

  @override
  String get visitProofTitle => 'సందర్శన రుజువు';

  @override
  String get visitExpectedScore => 'అంచనా స్కోరు';

  @override
  String get visitServerScore => 'సర్వర్ నుండి స్కోరు';

  @override
  String get visitConfirmFarmer => 'రైతు ధృవీకరణ';

  @override
  String get visitCheckOut => 'చెక్ అవుట్';

  @override
  String get visitCheckInPending =>
      'ఆన్‌లైన్ అయినప్పుడు చెక్ ఇన్ సింక్ అవుతుంది';

  @override
  String get visitCheckInSynced => 'చెక్ ఇన్ సింక్ అయింది';

  @override
  String get visitRejectedTitle => 'చెక్ ఇన్ తిరస్కరించబడింది';

  @override
  String visitRejectedOutside(int distance) {
    return 'సర్వర్ మిమ్మల్ని జియోఫెన్స్ బయట $distance మీ దూరంలో గుర్తించింది.';
  }

  @override
  String get visitRejectedNoTarget =>
      'మీ స్థానాన్ని పోల్చడానికి సర్వర్‌కు ఏమీ దొరకలేదు.';

  @override
  String get visitRetryFromFarm => 'పొలం నుండి మళ్లీ ప్రయత్నించండి';

  @override
  String visitRetryStillOutside(int distance) {
    return 'ఇంకా $distance మీ బయట ఉన్నారు. దగ్గరకు వెళ్లండి లేదా ఓవర్‌రైడ్ కోరండి.';
  }

  @override
  String get visitRetryQueued =>
      'మీ ప్రస్తుత స్థానంతో చెక్ ఇన్ మళ్లీ క్యూలో పెట్టబడింది.';

  @override
  String get proofGeofenceOverride =>
      'ఓవర్‌రైడ్ కోరబడింది; క్లస్టర్ హెడ్ కోసం వేచి ఉంది';

  @override
  String get proofGeofenceOutside => 'జియోఫెన్స్ బయట';

  @override
  String get proofPhotoDone => 'స్థానంతో ఫోటో తీయబడింది';

  @override
  String get proofDurationDone => 'కనీస వ్యవధి పూర్తయింది';

  @override
  String get proofIntegrityIssue =>
      'డివైస్ తనిఖీలలో సమస్యలు; ఈ భాగానికి 0 స్కోరు';

  @override
  String get visitConfirmTitle => 'రైతు ధృవీకరణ';

  @override
  String get visitConfirmIntro =>
      'ఈ సందర్శనను ధృవీకరించమని రైతును ఈ మార్గాలలో ఒకదాని ద్వారా అడగండి.';

  @override
  String get visitConfirmOtp => 'SMS ద్వారా OTP';

  @override
  String get visitConfirmOtpHelp =>
      'రైతు ఫోన్‌కు కోడ్ వెళుతుంది; దాన్ని ఇక్కడ టైప్ చేయండి.';

  @override
  String get visitConfirmPush => 'కిసాన్ యాప్‌లో అడగండి';

  @override
  String get visitConfirmPushHelp => 'రైతు తమ యాప్‌లో ధృవీకరించు నొక్కుతారు.';

  @override
  String get visitConfirmQr => 'QR చూపించండి';

  @override
  String get visitConfirmQrHelp =>
      'రైతు దీన్ని కిసాన్ యాప్‌తో స్కాన్ చేస్తారు.';

  @override
  String get visitConfirmNeedsNetwork =>
      'దీనికి నెట్‌వర్క్ కావాలి. ఆన్‌లైన్ అయినప్పుడు మళ్లీ ప్రయత్నించండి.';

  @override
  String get visitConfirmQrNeedsSync =>
      'QR కోసం ముందుగా ఒకసారి సింక్ కావాలి. ఒకసారి కనెక్ట్ చేసి తిరిగి రండి.';

  @override
  String get visitConfirmNotSynced =>
      'చెక్ ఇన్ ఇంకా సర్వర్‌కు చేరలేదు. సింక్ చేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get visitConfirmQueued =>
      'అభ్యర్థన సేవ్ అయింది. మీరు ఆన్‌లైన్ అయిన వెంటనే రైతు యాప్‌కు వెళుతుంది.';

  @override
  String get visitConfirmWaiting => 'రైతు కోసం వేచి ఉన్నాం…';

  @override
  String get visitConfirmWaitingPush =>
      'కిసాన్ యాప్‌లో రైతును అడిగాం. వారు ధృవీకరించగానే ఈ స్క్రీన్ అప్‌డేట్ అవుతుంది.';

  @override
  String get visitConfirmQrWaiting => 'రైతు స్కాన్ చేసే వరకు వేచి ఉన్నాం…';

  @override
  String get visitConfirmed => 'రైతు ధృవీకరించారు';

  @override
  String visitConfirmedVia(String channel) {
    return '$channel ద్వారా ధృవీకరించబడింది';
  }

  @override
  String visitConfirmOtpSent(String phone) {
    return '$phoneకు కోడ్ పంపబడింది';
  }

  @override
  String get visitConfirmAlready => 'ఈ సందర్శన ఇప్పటికే ధృవీకరించబడింది.';

  @override
  String get visitConfirmRefused =>
      'ఇప్పుడు రైతును ఈ విధంగా అడగలేము. మరో మార్గం ప్రయత్నించండి.';

  @override
  String get visitConfirmContinue => 'చెక్ అవుట్‌కు కొనసాగండి';

  @override
  String get visitConfirmLater => 'తర్వాత ధృవీకరించండి';

  @override
  String visitConfirmExpires(int minutes) {
    return '$minutes నిమిలో గడువు ముగుస్తుంది';
  }

  @override
  String get visitConfirmChooseAnother => 'మరో మార్గం ఎంచుకోండి';

  @override
  String get visitSummaryTitle => 'చెక్ అవుట్ సారాంశం';

  @override
  String get visitSummaryDuration => 'వ్యవధి';

  @override
  String get visitSummaryMissing => 'ఏమి తక్కువైంది';

  @override
  String get visitSummaryComplete => 'అన్నీ సరిగ్గా ఉన్నాయి';

  @override
  String get visitSummaryPending =>
      'తర్వాతి సింక్ తర్వాత సర్వర్ స్కోరును ధృవీకరిస్తుంది';

  @override
  String get visitSummaryServer => 'సర్వర్ స్కోరును ధృవీకరించింది';

  @override
  String get visitSummaryNotCheckedOut => 'ఈ సందర్శన ఇంకా కొనసాగుతోంది.';

  @override
  String get visitSummaryOverridePending => 'ఓవర్‌రైడ్ సమీక్ష కోసం వేచి ఉంది';

  @override
  String get visitDone => 'పూర్తయింది';

  @override
  String get syncEntityVisit => 'సందర్శన';

  @override
  String get syncEntityVisitPhoto => 'సందర్శన ఫోటో';

  @override
  String get syncEntityVisitConfirmation => 'రైతు ధృవీకరణ';

  @override
  String get catalogTitle => 'ఉత్పత్తులు';

  @override
  String catalogForFarmer(String name) {
    return '$name కోసం';
  }

  @override
  String get catalogSearchHint => 'పేరు, బ్రాండ్ లేదా మందు పదార్థం వెతకండి';

  @override
  String get catalogCategoryAll => 'అన్నీ';

  @override
  String get catalogCategorySeed => 'విత్తనాలు';

  @override
  String get catalogCategoryFertiliser => 'ఎరువులు';

  @override
  String get catalogCategoryPesticide => 'పురుగుమందులు';

  @override
  String get catalogCategoryFungicide => 'శిలీంద్రనాశకాలు';

  @override
  String get catalogCategoryHerbicide => 'కలుపు మందులు';

  @override
  String get catalogCategoryGrowth => 'పెరుగుదల ప్రోత్సాహకాలు';

  @override
  String get catalogCategoryTool => 'పనిముట్లు';

  @override
  String get catalogCategoryOther => 'ఇతరాలు';

  @override
  String catalogAsOf(String time) {
    return '$time నాటి ధరలు, స్టాక్';
  }

  @override
  String catalogStale(String time) {
    return 'ధరలు, స్టాక్ పాతవి కావచ్చు ($time నాటివి). ఇంటర్నెట్ ఉన్నప్పుడు రిఫ్రెష్ చేయండి.';
  }

  @override
  String get catalogNeverLoaded => 'ఉత్పత్తుల జాబితా ఇంకా ఈ ఫోన్‌లో లేదు';

  @override
  String get catalogNeverLoadedHelp =>
      'ఉత్పత్తులు, ధరలు డౌన్‌లోడ్ చేయడానికి ఇంటర్నెట్‌కు కనెక్ట్ అవ్వండి.';

  @override
  String get catalogRefresh => 'రిఫ్రెష్ చేయండి';

  @override
  String get catalogRefreshFailed =>
      'రిఫ్రెష్ కాలేదు. సేవ్ చేసిన ఉత్పత్తులు చూపిస్తున్నాం.';

  @override
  String get catalogEmpty => 'సరిపోయే ఉత్పత్తులు లేవు';

  @override
  String get catalogEmptyHelp => 'వేరే పేరు లేదా విభాగం ప్రయత్నించండి.';

  @override
  String get catalogStoreUnknown =>
      'దుకాణం ఇంకా తెలియదు. తదుపరి సింక్ తర్వాత స్టాక్ కనిపిస్తుంది.';

  @override
  String get productPriceEstimate => 'అంచనా ధర';

  @override
  String productStockNearest(int count) {
    return 'దగ్గరి దుకాణంలో $count స్టాక్‌లో ఉన్నాయి';
  }

  @override
  String productStockAsOf(String time) {
    return '$time నాటికి';
  }

  @override
  String productInCart(int count) {
    return 'కార్ట్‌లో $count';
  }

  @override
  String get cartEstimatedTotal => 'అంచనా మొత్తం';

  @override
  String get cartViewCart => 'కార్ట్ చూడండి';

  @override
  String get cartTitle => 'కార్ట్';

  @override
  String get cartEmpty => 'కార్ట్ ఖాళీగా ఉంది';

  @override
  String get cartEmptyHelp => 'జాబితా నుండి ఉత్పత్తులు జోడించండి.';

  @override
  String get cartAddMore => 'మరిన్ని ఉత్పత్తులు జోడించండి';

  @override
  String get cartSubtotal => 'ఉప మొత్తం (అంచనా)';

  @override
  String get cartTax => 'GST (అంచనా)';

  @override
  String get cartEstimateNote =>
      'ధరలు సేవ్ చేసిన ధరల జాబితా నుండి అంచనాలు. ఆర్డర్ సింక్ అయినప్పుడు దుకాణం తుది మొత్తం నిర్ధారిస్తుంది.';

  @override
  String get cartFulfilment => 'రైతుకు సరుకు ఎలా అందుతుంది?';

  @override
  String get fulfilmentPickup => 'దుకాణంలో తీసుకోవడం';

  @override
  String get fulfilmentDelivery => 'ఇంటికి డెలివరీ';

  @override
  String get cartChoosePayment => 'చెల్లింపు ఎంచుకోండి';

  @override
  String get cartDecrease => 'ఒకటి తగ్గించండి';

  @override
  String get cartIncrease => 'ఒకటి పెంచండి';

  @override
  String cartShortLine(String available, String requested) {
    return 'దుకాణంలో $available మాత్రమే ఉన్నాయి ($requested అడిగారు).';
  }

  @override
  String cartUseAvailable(String available) {
    return '$available ఉంచండి';
  }

  @override
  String get cartShortTitle =>
      'దుకాణంలో కొన్ని సరుకులు తక్కువగా ఉన్నాయి. పరిమాణం మార్చి మళ్లీ పంపండి.';

  @override
  String get checkoutTitle => 'చెల్లింపు';

  @override
  String get checkoutOrderAmount => 'ఆర్డర్ మొత్తం (అంచనా)';

  @override
  String get checkoutDuesAmount => 'వసూలు చేయాల్సిన మొత్తం (₹)';

  @override
  String checkoutDuesBalance(String amount) {
    return 'బాకీ $amount';
  }

  @override
  String checkoutDuesTooMuch(String amount) {
    return '$amount వరకు మొత్తం నమోదు చేయండి';
  }

  @override
  String get checkoutDuesInvalid => 'మొత్తం నమోదు చేయండి';

  @override
  String get checkoutPlaceOrder => 'ఆర్డర్ చేయండి';

  @override
  String get checkoutCollect => 'వసూలు చేయండి';

  @override
  String get checkoutNeedsInternet =>
      'ఇంటర్నెట్ కావాలి: నగదు లేదా అప్పు వాడండి';

  @override
  String get checkoutCreditOrdersOnly => 'అప్పు ఆర్డర్లకు మాత్రమే';

  @override
  String checkoutCreditLeft(String amount) {
    return 'మిగిలిన పరిమితి $amount';
  }

  @override
  String get checkoutOfflineNote =>
      'మీరు ఆఫ్‌లైన్‌లో ఉన్నారు. నగదు, అప్పు ఫోన్‌లో సేవ్ అయి ఇంటర్నెట్ వచ్చాక పంపబడతాయి.';

  @override
  String get checkoutOrderNotSynced =>
      'ఆర్డర్ ఇంకా సర్వర్‌కు చేరలేదు. ఇంటర్నెట్ ఉన్నప్పుడు మళ్లీ ప్రయత్నించండి లేదా నగదు తీసుకోండి.';

  @override
  String get checkoutNetworkError =>
      'సర్వర్‌ను చేరలేకపోయాం. ఇంటర్నెట్ చూసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get checkoutAlreadyPaid => 'ఈ ఆర్డర్‌కు ఇప్పటికే చెల్లింపు జరిగింది.';

  @override
  String get checkoutAmountMismatch =>
      'సర్వర్‌లో మొత్తం మారింది. ఆర్డర్ చూసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get checkoutNothingDue => 'ఈ రైతుకు బాకీ ఏమీ లేదు.';

  @override
  String checkoutRefused(String code) {
    return 'చెల్లింపు సృష్టించలేకపోయాం ($code).';
  }

  @override
  String get paymentCard => 'కార్డ్';

  @override
  String get paymentDone => 'పూర్తయింది';

  @override
  String get upiTitle => 'UPI QR';

  @override
  String get upiExpired => 'QR గడువు ముగిసింది';

  @override
  String get upiCollectCash => 'బదులుగా నగదు తీసుకోండి';

  @override
  String get linkTitle => 'చెల్లింపు లింక్';

  @override
  String get linkSentTitle => 'చెల్లింపు లింక్ పంపాం';

  @override
  String linkSentVia(String channel) {
    return '$channel ద్వారా పంపాం. లింక్ తెరిచి చెల్లించమని రైతుకు చెప్పండి.';
  }

  @override
  String get channelSms => 'SMS';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get linkResend => 'లింక్ మళ్లీ పంపండి';

  @override
  String get linkResent => 'లింక్ మళ్లీ పంపాం';

  @override
  String get linkCheckStatus => 'చెల్లింపు చూడండి';

  @override
  String linkValidUntil(String time) {
    return '$time వరకు చెల్లుతుంది';
  }

  @override
  String get cashTitle => 'నగదు రసీదు';

  @override
  String get cashAmount => 'తీసుకున్న నగదు';

  @override
  String get cashTakePhoto => 'రసీదు ఫోటో తీయండి';

  @override
  String get cashRetake => 'మళ్లీ తీయండి';

  @override
  String get cashSave => 'నగదు చెల్లింపు సేవ్ చేయండి';

  @override
  String get cashPhotoHelp =>
      'రైతుకు ఇచ్చిన రసీదు ఫోటో తీయండి. యాప్ కెమెరా మాత్రమే వాడవచ్చు.';

  @override
  String get cashPhotoBad =>
      'ఫోటో మసకగా లేదా చీకటిగా ఉంది. మంచి వెలుతురులో మళ్లీ తీయండి.';

  @override
  String get cashSaved =>
      'నగదు సేవ్ అయింది. దుకాణం సరిపోల్చడం పెండింగ్‌లో ఉంది.';

  @override
  String get cashPendingReconciliation =>
      'దుకాణం సరిపోల్చడం పెండింగ్: రోజు ముగింపులో దుకాణం నగదు తనిఖీ చేస్తుంది.';

  @override
  String get creditTitle => 'అప్పు అమ్మకం';

  @override
  String get creditQueued =>
      'ఫోన్‌లో సేవ్ అయింది. ఇంటర్నెట్ వచ్చినప్పుడు అప్పు పరిమితి చూస్తారు.';

  @override
  String get creditApprovedTitle => 'రైతు ఖాతాలో చేర్చాం';

  @override
  String get creditNeedsApprovalTitle => 'ఆమోదం కావాలి';

  @override
  String get creditNeedsApprovalBody =>
      'ఈ అమ్మకం రైతు అప్పు పరిమితి దాటింది. ఆమోదం కోసం క్లస్టర్ హెడ్‌కు పంపాం.';

  @override
  String get creditLimit => 'అప్పు పరిమితి';

  @override
  String get creditBalance => 'ప్రస్తుత బాకీ';

  @override
  String get creditShortfall => 'పరిమితి మించినది';

  @override
  String get creditSentToClusterHead => 'క్లస్టర్ హెడ్‌కు పంపాం';

  @override
  String get creditCheckAgain => 'ఆమోదం చూడండి';

  @override
  String get creditStillPending => 'ఇంకా ఆమోదం రాలేదు. తర్వాత మళ్లీ చూడండి.';

  @override
  String get creditOfflineCheck =>
      'ఆమోదం చూడటానికి ఇంటర్నెట్‌కు కనెక్ట్ అవ్వండి.';

  @override
  String get creditUseCash => 'బదులుగా నగదు తీసుకోండి';

  @override
  String get orderTitle => 'ఆర్డర్';

  @override
  String get orderPlacedTitle => 'ఆర్డర్ చేశాం';

  @override
  String get orderQueuedTitle => 'ఆర్డర్ సేవ్ అయింది, సింక్ కోసం వేచి ఉంది';

  @override
  String get orderQueuedHelp =>
      'ఫోన్‌కు ఇంటర్నెట్ రాగానే ఇది దుకాణానికి వెళుతుంది.';

  @override
  String get orderRejectedTitle => 'దుకాణం ఈ ఆర్డర్ తీసుకోలేకపోయింది';

  @override
  String get orderInsufficientStock => 'దుకాణంలో కొన్ని సరుకులు తక్కువ:';

  @override
  String orderShortLine(String product, String available, String requested) {
    return '$product: $available ఉన్నాయి, $requested అడిగారు';
  }

  @override
  String get orderSkuNotRecommendable =>
      'ఒక ఉత్పత్తికి ఈ పంట, పురుగుకు అనుమతి లేదు (లేబుల్ క్లెయిమ్). దాన్ని తీసేసి మళ్లీ పంపండి.';

  @override
  String get orderEditAndResend => 'మార్చి మళ్లీ పంపండి';

  @override
  String get orderSummary => 'సారాంశం';

  @override
  String get orderSubtotal => 'ఉప మొత్తం';

  @override
  String get orderTax => 'GST';

  @override
  String get orderTotal => 'మొత్తం';

  @override
  String get orderTotalEstimate => 'మొత్తం (అంచనా)';

  @override
  String get orderStatusTitle => 'స్థితి';

  @override
  String get orderStatusPlaced => 'ఆర్డర్ అయింది';

  @override
  String get orderStatusReserved => 'స్టాక్ కేటాయించారు';

  @override
  String get orderStatusPacked => 'ప్యాక్ అయింది';

  @override
  String get orderStatusReady => 'సిద్ధం';

  @override
  String get orderStatusHandedOver => 'అప్పగించారు';

  @override
  String get orderStatusDelivered => 'డెలివరీ అయింది';

  @override
  String get orderStatusCancelled => 'రద్దయింది';

  @override
  String get orderPayments => 'చెల్లింపులు';

  @override
  String get orderNoPayments => 'ఇంకా చెల్లింపు లేదు';

  @override
  String get orderShareInvoice => 'WhatsAppలో బిల్లు పంపండి';

  @override
  String get orderShareOffline =>
      'బిల్లు పంపడానికి ఇంటర్నెట్‌కు కనెక్ట్ అవ్వండి.';

  @override
  String get orderShareNoInvoice =>
      'దుకాణం ఆర్డర్ అప్పగించినప్పుడు బిల్లు ఇస్తుంది.';

  @override
  String get orderShareFailed => 'బిల్లు లింక్ రాలేదు. మళ్లీ ప్రయత్నించండి.';

  @override
  String orderShareText(String number, String url) {
    return 'బిల్లు $number: $url';
  }

  @override
  String orderInvoiceNo(String number) {
    return 'బిల్లు $number';
  }

  @override
  String get orderCollectPayment => 'చెల్లింపు తీసుకోండి';

  @override
  String get orderPendingSync => 'సింక్ కోసం వేచి ఉంది';

  @override
  String get orderRejected => 'చూడాలి';

  @override
  String get ordersTitle => 'ఆర్డర్లు';

  @override
  String get ordersEmpty => 'ఇంకా ఆర్డర్లు లేవు';

  @override
  String get ordersEmptyHelp =>
      'రైతుల కోసం మీరు చేసిన ఆర్డర్లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get ordersNew => 'కొత్త ఆర్డర్';

  @override
  String get ordersCollections => 'వసూళ్లు';

  @override
  String get ordersPickFarmer => 'రైతును ఎంచుకోండి';

  @override
  String get khataTitle => 'ఖాతా';

  @override
  String khataAsOf(String time) {
    return '$time నాటికి';
  }

  @override
  String khataOfflineAsOf(String time) {
    return 'ఆఫ్‌లైన్: $timeకు సేవ్ చేసిన ఖాతా చూపిస్తున్నాం';
  }

  @override
  String get khataNotLoaded => 'ఖాతా ఇంకా ఈ ఫోన్‌లో లేదు';

  @override
  String get khataNotLoadedHelp =>
      'రైతు ఖాతా తెచ్చుకోవడానికి ఇంటర్నెట్‌కు కనెక్ట్ అవ్వండి.';

  @override
  String khataOverdue(String amount) {
    return 'గడువు దాటిన బాకీ $amount';
  }

  @override
  String get khataBucket0to30 => '0–30 రోజులు';

  @override
  String get khataBucket31to60 => '31–60 రోజులు';

  @override
  String get khataBucket61to90 => '61–90 రోజులు';

  @override
  String get khataBucket90plus => '90+ రోజులు';

  @override
  String khataDueHarvest(String date, String month) {
    return 'గడువు $date · పంట $month';
  }

  @override
  String get khataEntryOrder => 'అప్పు అమ్మకం';

  @override
  String get khataEntryPayment => 'చెల్లింపు అందింది';

  @override
  String get khataEntryAdjustment => 'సర్దుబాటు';

  @override
  String get khataPaymentHistory => 'చెల్లింపుల చరిత్ర';

  @override
  String get khataNoPayments => 'ఇంకా చెల్లింపులు లేవు';

  @override
  String get khataPendingCollections => 'వసూలైంది, ఇంకా ఖాతాలో లేదు';

  @override
  String get collectionsTitle => 'వసూళ్లు';

  @override
  String get collectionsToday => 'ఈరోజు';

  @override
  String get collectionsWeek => 'ఈ వారం';

  @override
  String get collectionsTotal => 'మొత్తం వసూలు';

  @override
  String get collectionsEmpty => 'ఇంకా వసూళ్లు లేవు';

  @override
  String get collectionsEmptyHelp =>
      'మీరు వసూలు చేసిన చెల్లింపులు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get collectionStateWaitingToSync => 'సింక్ కోసం వేచి ఉంది';

  @override
  String get collectionStatePendingReconciliation => 'సరిపోల్చడం పెండింగ్';

  @override
  String get collectionStateWaiting => 'చెల్లింపు కోసం వేచి ఉంది';

  @override
  String get collectionStatePaid => 'చెల్లించారు';

  @override
  String get collectionStateOnKhata => 'ఖాతాలో';

  @override
  String get collectionStateApprovalNeeded => 'ఆమోదం కావాలి';

  @override
  String get collectionStateFailed => 'విఫలమైంది';

  @override
  String get syncEntityOrder => 'ఆర్డర్';

  @override
  String get syncEntityPayment => 'చెల్లింపు';
}

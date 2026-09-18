// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class CoreLocalizationsHi extends CoreLocalizations {
  CoreLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appNameAgent => 'मित्र';

  @override
  String get appNameFarmer => 'किसान';

  @override
  String get splashTagline => 'आपके खेत के लिए भरोसेमंद सलाह';

  @override
  String get actionContinue => 'आगे बढ़ें';

  @override
  String get actionBack => 'पीछे';

  @override
  String get actionNext => 'अगला';

  @override
  String get actionRetry => 'फिर से कोशिश करें';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get actionDone => 'हो गया';

  @override
  String get actionSkip => 'छोड़ें';

  @override
  String get actionClose => 'बंद करें';

  @override
  String get loading => 'लोड हो रहा है';

  @override
  String get languagePickerTitle => 'अपनी भाषा चुनें';

  @override
  String get languagePickerSubtitle => 'सुनने के लिए स्पीकर दबाएँ';

  @override
  String get languagePlayAudio => 'सुनें';

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
  String get languageEnglishName => 'अंग्रेज़ी';

  @override
  String get languageTeluguName => 'तेलुगु';

  @override
  String get languageKannadaName => 'कन्नड़';

  @override
  String get languageHindiName => 'हिन्दी';

  @override
  String get languageMarathiName => 'मराठी';

  @override
  String get phoneLoginTitle => 'अपना मोबाइल नंबर डालें';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'हम SMS से 6 अंकों का OTP भेजेंगे';

  @override
  String get phoneInvalid => 'सही 10 अंकों का मोबाइल नंबर डालें';

  @override
  String get phoneSendOtp => 'OTP भेजें';

  @override
  String get otpTitle => 'OTP डालें';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone पर भेजा गया';
  }

  @override
  String get otpLabel => '6 अंकों का OTP';

  @override
  String get otpResend => 'OTP दोबारा भेजें';

  @override
  String otpResendIn(int seconds) {
    return '$seconds सेकंड में दोबारा भेजें';
  }

  @override
  String get otpInvalid => 'OTP गलत है। फिर से कोशिश करें।';

  @override
  String get otpVerify => 'जाँचें';

  @override
  String otpDigitLabel(int index) {
    return '6 में से $indexवाँ अंक';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count कोशिशें बाकी';
  }

  @override
  String otpLocked(int minutes) {
    return 'बहुत बार गलत OTP डाला। $minutes मिनट बाद फिर कोशिश करें।';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'बहुत बार OTP माँगा गया। $minutes मिनट बाद फिर कोशिश करें।';
  }

  @override
  String get otpExpired => 'यह OTP समाप्त हो गया है। नया माँगें।';

  @override
  String get phoneNotFound =>
      'यह नंबर पंजीकृत नहीं है। अपने मैनेजर से जोड़ने को कहें।';

  @override
  String get networkError =>
      'कनेक्शन नहीं है। नेटवर्क जाँचें और फिर कोशिश करें।';

  @override
  String get consentTitle => 'आपकी लोकेशन और डेटा';

  @override
  String get consentPoint1 => 'हम आपकी लोकेशन और विज़िट की फ़ोटो लेते हैं।';

  @override
  String get consentPoint2 => 'लोकेशन सिर्फ़ ड्यूटी के समय ली जाती है।';

  @override
  String get consentPoint3 =>
      'इसका उपयोग यात्रा भत्ते और विज़िट क्रेडिट के लिए होता है।';

  @override
  String get consentPoint4 =>
      'आपके मैनेजर और मालिक इसे देख सकते हैं। किसान नहीं।';

  @override
  String get consentAgree => 'मैं सहमत हूँ';

  @override
  String get consentPolicyLink => 'पूरी नीति पढ़ें';

  @override
  String get consentDataCardTitle =>
      'फ़सल की सलाह के लिए मेरा डेटा इस्तेमाल करें';

  @override
  String get consentDataCardBody =>
      'आपकी मदद के लिए हम आपकी फ़सल की फ़ोटो और खेत की जानकारी देखते हैं।';

  @override
  String get consentRequired => 'ज़रूरी';

  @override
  String get consentOffersCardTitle => 'मुझे ऑफ़र और सुझाव भेजें';

  @override
  String get consentOffersCardBody => 'उत्पादों और खेती के सुझावों के संदेश।';

  @override
  String get consentOptional => 'वैकल्पिक';

  @override
  String get consentReadAloud => 'पढ़कर सुनाएँ';

  @override
  String get dutyOn => 'ड्यूटी पर';

  @override
  String get dutyOff => 'ड्यूटी पर नहीं';

  @override
  String get dutyGoOn => 'ड्यूटी शुरू करें';

  @override
  String get dutyGoOff => 'ड्यूटी खत्म करें';

  @override
  String dutyElapsed(String duration) {
    return '$duration से ड्यूटी पर';
  }

  @override
  String get dutyLocationNote => 'लोकेशन सिर्फ़ ड्यूटी के समय चालू रहती है';

  @override
  String get syncSynced => 'सिंक हो गया';

  @override
  String syncPending(int count) {
    return '$count बाकी';
  }

  @override
  String get syncFailed => 'सिंक विफल';

  @override
  String get offlineBanner =>
      'आप ऑफ़लाइन हैं। आपका काम सेव है और बाद में सिंक होगा।';

  @override
  String get syncSyncing => 'सिंक हो रहा है…';

  @override
  String get syncDetailsTitle => 'सिंक विवरण';

  @override
  String get syncNow => 'अभी सिंक करें';

  @override
  String syncLastSync(String time) {
    return 'आख़िरी सिंक $time';
  }

  @override
  String get syncNeverSynced => 'अभी तक सिंक नहीं हुआ';

  @override
  String get syncAllDone => 'सब कुछ सिंक हो गया';

  @override
  String get syncAllDoneHelp =>
      'ऑफ़लाइन सहेजे गए नए किसान, खेत और फ़ोटो सर्वर तक पहुँचने तक यहाँ दिखेंगे।';

  @override
  String syncPendingSection(int count) {
    return 'सिंक की प्रतीक्षा में ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'ध्यान देना ज़रूरी ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'फ़ोटो अपलोड की प्रतीक्षा में';

  @override
  String syncPhotoUploads(int count) {
    return 'अपलोड हो रही फ़ोटो: $count';
  }

  @override
  String get syncTransportError =>
      'सर्वर से संपर्क नहीं हो सका। यह अपने आप फिर कोशिश करेगा।';

  @override
  String syncNextAttempt(String time) {
    return 'अगली कोशिश $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'नया';

  @override
  String get syncActionUpdate => 'संपादित';

  @override
  String get syncActionDelete => 'हटाया गया';

  @override
  String get syncEntityFarmer => 'किसान';

  @override
  String get syncEntityFarm => 'खेत';

  @override
  String get syncEntityCropPlot => 'फ़सल प्लॉट';

  @override
  String get syncEntityConsent => 'सहमति';

  @override
  String get syncEntityOther => 'आइटम';

  @override
  String syncSavedAt(String time) {
    return 'सहेजा गया $time';
  }

  @override
  String get syncRejectedDefault =>
      'सर्वर ने यह आइटम स्वीकार नहीं किया। इसे संपादित करके फिर कोशिश करें।';

  @override
  String get syncRetryAll => 'सभी फिर कोशिश करें';

  @override
  String get syncDiscard => 'हटा दें';

  @override
  String get visitVerified => 'सत्यापित';

  @override
  String get visitPartial => 'आंशिक';

  @override
  String get visitUnverified => 'असत्यापित';

  @override
  String visitScore(int score) {
    return '100 में से $score अंक';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String get visitPurposeAdvisory => 'सलाह';

  @override
  String get visitPurposeScouting => 'खेत निरीक्षण';

  @override
  String get visitPurposeDemo => 'डेमो';

  @override
  String get visitPurposeCollection => 'वसूली';

  @override
  String get visitPurposeSale => 'बिक्री';

  @override
  String get visitPurposeMeeting => 'बैठक';

  @override
  String get proofGeofence => 'खेत की सीमा के अंदर';

  @override
  String get proofGeofenceMissing => 'आप खेत की सीमा से बाहर थे';

  @override
  String get proofPhoto => 'फ़ोटो ली गई';

  @override
  String get proofPhotoMissing => 'विज़िट के दौरान फ़ोटो नहीं ली';

  @override
  String get proofFarmerConfirmed => 'किसान ने पुष्टि की';

  @override
  String get proofFarmerConfirmedMissing => 'किसान ने विज़िट की पुष्टि नहीं की';

  @override
  String get proofDuration => 'खेत पर न्यूनतम समय पूरा';

  @override
  String get proofDurationMissing => 'विज़िट 10 मिनट से कम थी';

  @override
  String get proofDone => 'पूरा';

  @override
  String get proofMissing => 'नहीं';

  @override
  String get cameraHoldSteady => 'स्थिर रखें';

  @override
  String get cameraGoodLight => 'अच्छी रोशनी';

  @override
  String get cameraFillFrame => 'फ़्रेम भरें';

  @override
  String get cameraLeafFrame => 'पत्ती को फ़्रेम के अंदर रखें';

  @override
  String get photoReviewHeading => 'अपनी फ़ोटो जाँचें';

  @override
  String photoReviewTitle(int index, int total) {
    return 'फ़ोटो $index / $total';
  }

  @override
  String get photoQualityOk => 'अच्छी फ़ोटो';

  @override
  String get photoQualityBlurry => 'धुंधली है';

  @override
  String get photoQualityDark => 'बहुत अंधेरा है';

  @override
  String get photoQualityChecking => 'फ़ोटो जाँच रहे हैं';

  @override
  String get photoTipBlurry =>
      'फ़ोन को स्थिर पकड़ें, पत्ते पर टैप करके फ़ोकस करें और फिर से लें';

  @override
  String get photoTipDark =>
      'अच्छी रोशनी में जाएँ, छाया से बाहर आएँ और फिर से लें';

  @override
  String get photoTipOk => 'फ़ोटो अच्छी है';

  @override
  String get photoRetake => 'फिर से लें';

  @override
  String get photoUse => 'यह फ़ोटो इस्तेमाल करें';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get confidenceHigh => 'उच्च भरोसा';

  @override
  String get confidenceMedium => 'मध्यम भरोसा';

  @override
  String get confidenceLow => 'अस्थायी';

  @override
  String get diagnosisSymptomsTitle => 'ये लक्षण जाँचें';

  @override
  String get diagnosisProvisionalNote =>
      'हमारे विशेषज्ञ 24 घंटे में पुष्टि करेंगे';

  @override
  String get diagnosisProblem => 'समस्या';

  @override
  String get treatmentOrganic => 'जैविक';

  @override
  String get treatmentChemical => 'रासायनिक';

  @override
  String get treatmentActiveIngredient => 'सक्रिय तत्व';

  @override
  String get treatmentDosePerAcre => 'प्रति एकड़';

  @override
  String get treatmentDosePerTank => 'प्रति 15 ली टंकी';

  @override
  String treatmentSafetyInterval(int days) {
    return 'कटाई से पहले $days दिन रुकें';
  }

  @override
  String get treatmentPpeGloves => 'दस्ताने';

  @override
  String get treatmentPpeMask => 'मास्क';

  @override
  String get treatmentPpeGoggles => 'चश्मा';

  @override
  String get treatmentPpeTitle => 'पहनें';

  @override
  String get ownBrand => 'अपना ब्रांड';

  @override
  String get productAdd => 'जोड़ें';

  @override
  String get productAdded => 'जोड़ा गया';

  @override
  String productStockAtStore(int count, String store) {
    return '$store में $count स्टॉक में';
  }

  @override
  String get productOutOfStock => 'स्टॉक नहीं';

  @override
  String get productPack => 'पैक';

  @override
  String cartItems(int count) {
    return '$count चीज़ें';
  }

  @override
  String get cartTotal => 'कुल';

  @override
  String get cartCheckout => 'भुगतान करें';

  @override
  String get paymentMethodTitle => 'आप कैसे भुगतान करेंगे?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'स्कैन करके अभी भुगतान करें';

  @override
  String get paymentLink => 'भुगतान लिंक';

  @override
  String get paymentLinkHint => 'SMS या WhatsApp से भेजें';

  @override
  String get paymentCash => 'नकद';

  @override
  String get paymentCashHint => 'नकद लें और रसीद दें';

  @override
  String get paymentCredit => 'उधार';

  @override
  String get paymentCreditHint => 'किसान के खाते में जोड़ें';

  @override
  String get upiWaiting => 'भुगतान का इंतज़ार है';

  @override
  String get upiPaid => 'भुगतान मिल गया';

  @override
  String get upiFailed => 'भुगतान विफल';

  @override
  String upiExpiresIn(String time) {
    return '$time में समाप्त होगा';
  }

  @override
  String get upiAmount => 'राशि';

  @override
  String get upiScanHint => 'किसान से किसी भी UPI ऐप से स्कैन करने को कहें';

  @override
  String get upiRetry => 'नया QR दिखाएँ';

  @override
  String get khataBalance => 'बकाया राशि';

  @override
  String khataDueDate(String date) {
    return '$date तक देय';
  }

  @override
  String get khataDebit => 'दिया';

  @override
  String get khataCredit => 'मिला';

  @override
  String get khataNoEntries => 'अभी कोई प्रविष्टि नहीं';

  @override
  String get khataPayNow => 'अभी भुगतान करें';

  @override
  String get khataCollect => 'वसूल करें';

  @override
  String get emptyDefaultTitle => 'अभी यहाँ कुछ नहीं है';

  @override
  String get emptyDefaultHelp => 'जोड़ने के बाद चीज़ें यहाँ दिखेंगी।';

  @override
  String get errorTitle => 'कुछ गड़बड़ हो गई';

  @override
  String get errorHelp => 'कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get ratingTitle => 'अपनी विज़िट को रेटिंग दें';

  @override
  String get rating1 => 'बहुत खराब';

  @override
  String get rating2 => 'खराब';

  @override
  String get rating3 => 'ठीक';

  @override
  String get rating4 => 'अच्छा';

  @override
  String get rating5 => 'बहुत अच्छा';

  @override
  String stepperStepOf(int current, int total) {
    return '$total में से चरण $current';
  }

  @override
  String farmerLastVisit(String date) {
    return 'पिछली विज़िट $date';
  }

  @override
  String get farmerNoVisit => 'अभी कोई विज़िट नहीं';

  @override
  String farmerBalanceDue(String amount) {
    return 'बकाया $amount';
  }

  @override
  String get farmerVillage => 'गाँव';

  @override
  String get statTrendUp => 'बढ़ा';

  @override
  String get statTrendDown => 'घटा';

  @override
  String get statTrendFlat => 'कोई बदलाव नहीं';

  @override
  String get stageSowing => 'बुवाई';

  @override
  String get stageVegetative => 'बढ़वार';

  @override
  String get stageFlowering => 'फूल';

  @override
  String get stageFruiting => 'फल';

  @override
  String get stageHarvest => 'कटाई';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeSunlight => 'धूप';

  @override
  String get settingsTitle => 'सेटिंग';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get skeletonLoading => 'सामग्री लोड हो रही है';

  @override
  String get farmersTitle => 'किसान';

  @override
  String get farmersSearchHint => 'नाम, फ़ोन या गाँव खोजें';

  @override
  String get farmersAddFarmer => 'किसान जोड़ें';

  @override
  String get farmersEmptyTitle => 'अभी कोई किसान नहीं';

  @override
  String get farmersEmptyHelp =>
      'भेंट और ऑर्डर शुरू करने के लिए पहला किसान जोड़ें।';

  @override
  String get farmersNoResults => 'आपकी खोज से मेल खाता कोई किसान नहीं';

  @override
  String get farmersFilterVillage => 'गाँव';

  @override
  String get farmersFilterCrop => 'फ़सल';

  @override
  String get farmersFilterAll => 'सभी';

  @override
  String farmersCount(int count) {
    return '$count किसान';
  }

  @override
  String get farmerPendingSync => 'ऑनलाइन होने पर सिंक होगा';

  @override
  String get farmerPhoneUnverified => 'फ़ोन सत्यापित नहीं';

  @override
  String get farmerRejected => 'ध्यान चाहिए';

  @override
  String get regTitle => 'किसान जोड़ें';

  @override
  String get regStepBasics => 'किसान का विवरण';

  @override
  String get regStepBoundary => 'खेत की सीमा';

  @override
  String get regStepCrops => 'फ़सलें';

  @override
  String get regStepConsent => 'सहमति';

  @override
  String get regStepReview => 'जाँचें और सहेजें';

  @override
  String get regResumeDraft => 'जहाँ छोड़ा था वहीं से जारी';

  @override
  String get regDiscardDraft => 'ड्राफ़्ट हटाएँ';

  @override
  String get regFixIssues => 'आगे बढ़ने के लिए चिह्नित फ़ील्ड ठीक करें';

  @override
  String get regNameLabel => 'किसान का नाम';

  @override
  String get regNameHint => 'पहचान पत्र के अनुसार';

  @override
  String get regPhoneLabel => 'किसान का मोबाइल नंबर';

  @override
  String get regPhoneHelper => 'किसान को OTP भेजा जाएगा';

  @override
  String get regSendOtpToFarmer => 'किसान को OTP भेजें';

  @override
  String get regOtpSent => 'किसान को OTP भेजा गया। उनसे कोड पूछें।';

  @override
  String get regPhoneVerified => 'फ़ोन सत्यापित';

  @override
  String get regVerifyLater => 'बाद में सत्यापित करें';

  @override
  String get regVerifyLaterNote =>
      'सिग्नल नहीं? अभी सहेजें और किसान प्रोफ़ाइल से फ़ोन सत्यापित करें।';

  @override
  String get regVerifyLaterChosen => 'बाद में सत्यापित होगा';

  @override
  String get regDuplicatePhone => 'इस नंबर वाला किसान पहले से मौजूद है';

  @override
  String get regDuplicateOpen => 'मौजूदा किसान खोलें';

  @override
  String get regVillageLabel => 'गाँव';

  @override
  String get regVillageHint => 'गाँव चुनें';

  @override
  String get regVillageTyped => 'गाँव का नाम';

  @override
  String get regVillageNoneSynced =>
      'पहले सिंक के बाद गाँव लोड होंगे। अभी गाँव का नाम टाइप करें।';

  @override
  String get regLandmarkLabel => 'पहचान चिह्न';

  @override
  String get regLandmarkHint => 'मंदिर, स्कूल के पास…';

  @override
  String get regLanguageLabel => 'किसान की भाषा';

  @override
  String get regOwnershipLabel => 'ज़मीन';

  @override
  String get regBoundaryWalk => 'चारों ओर चलें';

  @override
  String get regBoundaryTap => 'कोने टैप करें';

  @override
  String get regStartWalk => 'चलना शुरू करें';

  @override
  String get regStopWalk => 'रोकें';

  @override
  String get regClosePolygon => 'सीमा बंद करें';

  @override
  String get regUndoPoint => 'बिंदु हटाएँ';

  @override
  String get regClearBoundary => 'साफ़ करें';

  @override
  String regPointsCount(int count) {
    return '$count बिंदु';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS सटीकता ±$metres मी';
  }

  @override
  String get regAccuracyWaiting => 'GPS की प्रतीक्षा…';

  @override
  String get regLocationOff => 'सीमा पर चलने के लिए लोकेशन चालू करें';

  @override
  String get regLocationDenied => 'सीमा पर चलने के लिए लोकेशन अनुमति चाहिए';

  @override
  String get regTapHint => 'नक्शे पर खेत के चारों कोने टैप करें';

  @override
  String get regWalkHint =>
      'खेत के किनारे-किनारे चलें। चलते हुए बिंदु जुड़ते जाएँगे।';

  @override
  String regComputedArea(String acres) {
    return 'मापा क्षेत्रफल $acres एकड़';
  }

  @override
  String get regAreaLabel => 'क्षेत्रफल एकड़ में';

  @override
  String get regAreaHint => 'जैसा किसान बताए';

  @override
  String get regUseMeasured => 'मापा हुआ लें';

  @override
  String get regAreaWarning =>
      'दर्ज क्षेत्रफल मापे गए क्षेत्रफल से 30% से अधिक अलग है। सहेजने से पहले जाँचें।';

  @override
  String get regBoundaryInvalid =>
      'सीमा खुद को काट रही है। आख़िरी बिंदु हटाकर फिर कोशिश करें।';

  @override
  String get regFarmNameLabel => 'खेत का नाम (वैकल्पिक)';

  @override
  String get regFarmNameHint => 'घर का खेत';

  @override
  String get regSoilLabel => 'मिट्टी का प्रकार';

  @override
  String get regIrrigationLabel => 'सिंचाई';

  @override
  String get regFarmPhoto => 'खेत की फ़ोटो (वैकल्पिक)';

  @override
  String get regTakePhoto => 'फ़ोटो लें';

  @override
  String get regPhotoAdded => 'फ़ोटो जोड़ी गई';

  @override
  String get regPhotoRemove => 'हटाएँ';

  @override
  String regFarmPhotosCount(int count) {
    return '$count फ़ोटो';
  }

  @override
  String get regCropsHelp => 'इस मौसम में इस खेत में उग रही हर फ़सल जोड़ें।';

  @override
  String get regAddCrop => 'फ़सल जोड़ें';

  @override
  String get regCropLabel => 'फ़सल';

  @override
  String get regVarietyLabel => 'किस्म';

  @override
  String get regVarietyHint => 'जैसे MTU-1010';

  @override
  String get regSowingDateLabel => 'बुवाई की तारीख़';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'मौसम: $season';
  }

  @override
  String get regPlotAreaLabel => 'क्षेत्रफल (एकड़, वैकल्पिक)';

  @override
  String get regRemoveCrop => 'फ़सल हटाएँ';

  @override
  String regPlotTitle(int index) {
    return 'फ़सल $index';
  }

  @override
  String get regAddFarm => 'एक और खेत जोड़ें';

  @override
  String regFarmsCount(int count) {
    return '$count खेत';
  }

  @override
  String regFarmIndex(int index) {
    return 'खेत $index';
  }

  @override
  String get regConsentIntro => 'इसे किसान को उनकी भाषा में पढ़कर सुनाएँ।';

  @override
  String get regConsentNotice =>
      'फ़सल सलाह देने और भेंट का रिकॉर्ड रखने के लिए हम आपका नाम, फ़ोन, गाँव और खेत का विवरण रखेंगे। आप हमें कभी भी रोकने को कह सकते हैं।';

  @override
  String get regConsentMarketingNotice =>
      'आपकी अनुमति से हम SMS या WhatsApp पर ऑफ़र और खेती के सुझाव भी भेजेंगे।';

  @override
  String get regConsentGiven => 'किसान सहमत हैं';

  @override
  String get regReviewFarmer => 'किसान';

  @override
  String get regReviewFarms => 'खेत और फ़सलें';

  @override
  String get regReviewConsent => 'सहमति';

  @override
  String get regReviewSyncNote =>
      'अभी इस फ़ोन में सहेजा गया; नेटवर्क आने पर सर्वर को भेजा जाएगा।';

  @override
  String get regSave => 'किसान सहेजें';

  @override
  String get regSaveFarm => 'खेत सहेजें';

  @override
  String get regEdit => 'संपादित करें';

  @override
  String get regSaved => 'किसान सहेजा गया';

  @override
  String get regIssueName => 'किसान का नाम दर्ज करें';

  @override
  String get regIssuePhoneUnverified =>
      'फ़ोन सत्यापित करें या बाद में सत्यापित करें चुनें';

  @override
  String get regIssueVillage => 'गाँव चुनें';

  @override
  String get regIssueLanguage => 'किसान की भाषा चुनें';

  @override
  String get regIssueBoundary => 'सीमा के कम से कम 3 बिंदु चिह्नित करें';

  @override
  String get regIssueArea => 'क्षेत्रफल एकड़ में दर्ज करें';

  @override
  String get regIssueCrop => 'कम से कम एक फ़सल जोड़ें';

  @override
  String get regIssueSowingDate => 'हर फ़सल की बुवाई की तारीख़ दर्ज करें';

  @override
  String get regIssueConsent => 'पंजीकरण के लिए डेटा सहमति ज़रूरी है';

  @override
  String get soilBlack => 'काली मिट्टी';

  @override
  String get soilRed => 'लाल मिट्टी';

  @override
  String get soilSandy => 'रेतीली मिट्टी';

  @override
  String get soilLoamy => 'दोमट मिट्टी';

  @override
  String get soilClay => 'चिकनी मिट्टी';

  @override
  String get soilAlluvial => 'जलोढ़ मिट्टी';

  @override
  String get soilLaterite => 'लैटेराइट मिट्टी';

  @override
  String get irrigationRainfed => 'वर्षा आधारित';

  @override
  String get irrigationBorewell => 'बोरवेल';

  @override
  String get irrigationCanal => 'नहर';

  @override
  String get irrigationTank => 'तालाब';

  @override
  String get irrigationOpenWell => 'खुला कुआँ';

  @override
  String get irrigationDrip => 'ड्रिप';

  @override
  String get irrigationSprinkler => 'स्प्रिंकलर';

  @override
  String get ownershipOwn => 'अपनी';

  @override
  String get ownershipLeased => 'पट्टे पर';

  @override
  String get seasonKharif => 'ख़रीफ़';

  @override
  String get seasonRabi => 'रबी';

  @override
  String get seasonZaid => 'ज़ायद (गर्मी)';

  @override
  String get profileTabOverview => 'सारांश';

  @override
  String get profileTabVisits => 'भेंट';

  @override
  String get profileTabDiagnoses => 'निदान';

  @override
  String get profileTabOrders => 'ऑर्डर';

  @override
  String get profileTabKhata => 'खाता';

  @override
  String get profileStartVisit => 'भेंट शुरू करें';

  @override
  String get profileScout => 'फ़सल जाँच';

  @override
  String get profileNewOrder => 'नया ऑर्डर';

  @override
  String get profileCollect => 'वसूली';

  @override
  String get profileComingSoon => 'आगामी अपडेट में आएगा';

  @override
  String get profileVisitsEmpty => 'अभी कोई भेंट नहीं';

  @override
  String get profileDiagnosesEmpty => 'अभी कोई निदान नहीं';

  @override
  String get profileOrdersEmpty => 'अभी कोई ऑर्डर नहीं';

  @override
  String get profileKhataEmpty => 'अभी खाते में कोई प्रविष्टि नहीं';

  @override
  String get profilePhone => 'फ़ोन';

  @override
  String get profileLandmark => 'पहचान चिह्न';

  @override
  String get profileLanguage => 'भाषा';

  @override
  String get profileOwnership => 'ज़मीन';

  @override
  String get profileFarms => 'खेत';

  @override
  String profileAcres(String acres) {
    return '$acres एकड़';
  }

  @override
  String get profileAddFarm => 'खेत जोड़ें';

  @override
  String get profileEditFarm => 'खेत संपादित करें';

  @override
  String profileFarmPlots(int count) {
    return '$count फ़सलें';
  }

  @override
  String get profileNoFarms => 'अभी कोई खेत नहीं';

  @override
  String get profileDuplicateTitle => 'डुप्लिकेट — मिलाएँ?';

  @override
  String get profileDuplicateBody =>
      'सर्वर पर इस नंबर वाला किसान पहले से है। मौजूदा रिकॉर्ड खोलकर विवरण मिलाएँ।';

  @override
  String get profileRejectedTitle => 'सिंक अस्वीकृत';

  @override
  String get profileRejectedHelp =>
      'ठीक करके फिर कोशिश करने के लिए सिंक विवरण खोलें।';

  @override
  String get profileNotFound => 'किसान नहीं मिला';

  @override
  String get profileVerifyPhone => 'फ़ोन सत्यापित करें';

  @override
  String get consentGiven => 'दी गई';

  @override
  String get consentNotGiven => 'नहीं दी गई';

  @override
  String get farmEditTitle => 'खेत संपादित करें';

  @override
  String get farmAddTitle => 'खेत जोड़ें';

  @override
  String get mapNoBoundary => 'अभी कोई सीमा नहीं';

  @override
  String get mapAttribution => '© OpenStreetMap योगदानकर्ता';

  @override
  String get mapCurrentPosition => 'आपकी स्थिति';

  @override
  String mapCorner(int index) {
    return 'कोना $index';
  }

  @override
  String get mapFarmBoundary => 'खेत की सीमा';

  @override
  String get dutyNotificationTitle => 'ड्यूटी पर — लोकेशन चालू';

  @override
  String get dutyChannelName => 'ड्यूटी';

  @override
  String get dutyAlertsChannelName => 'ड्यूटी अलर्ट';

  @override
  String get dutyPromptTitle => 'अभी भी ड्यूटी पर हैं?';

  @override
  String dutyPromptBody(String time) {
    return '$time पर समाप्त होगी';
  }

  @override
  String get dutyEndedTitle => 'ड्यूटी समाप्त';

  @override
  String dutyAutoEndedBody(String time) {
    return 'आपका दिन $time पर अपने आप समाप्त हो गया।';
  }

  @override
  String get dutyServerEndedBody =>
      'सर्वर ने आपकी ड्यूटी समाप्त कर दी (निष्क्रियता या दिन का अंत)।';

  @override
  String dutyAutoEndAt(String time) {
    return '$time पर अपने आप समाप्त होगी';
  }

  @override
  String get dutyBlockedPolicy =>
      'ड्यूटी पर जाने के लिए लोकेशन नीति स्वीकार करें';

  @override
  String get dutyReviewPolicy => 'नीति देखें';

  @override
  String dutyPointsPending(int count) {
    return '$count पॉइंट अपलोड की प्रतीक्षा में';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'आप पहले से दूसरे डिवाइस पर ड्यूटी पर हैं। यह बंद ही रहेगा।';

  @override
  String get dutyNoticePolicy =>
      'ड्यूटी पर जाने से पहले वर्तमान लोकेशन नीति स्वीकार करें।';

  @override
  String get dutyNoticeLocationUnavailable =>
      'आपकी लोकेशन नहीं मिल सकी। लोकेशन चालू करके फिर कोशिश करें।';

  @override
  String get integrityBanner =>
      'कुछ डिवाइस जाँचों में समस्या मिली; विज़िट की समीक्षा हो सकती है।';

  @override
  String get disclosureIntro =>
      'शुरू करने से पहले, यहाँ बताया गया है कि मित्र क्या दर्ज करता है और क्यों।';

  @override
  String disclosureVersion(String version) {
    return 'नीति संस्करण $version';
  }

  @override
  String get disclosureUpdated =>
      'लोकेशन नीति बदल गई है। कृपया नया संस्करण पढ़कर स्वीकार करें।';

  @override
  String get policySheetTitle => 'लोकेशन नीति';

  @override
  String get locationPolicyText =>
      'मित्र लोकेशन नीति (संस्करण 2026-09-v1)\n\n1. हम क्या इकट्ठा करते हैं। जब आप ड्यूटी पर होते हैं, मित्र आपकी लोकेशन (अक्षांश, देशांतर, सटीकता, गति, दिशा), समय, बैटरी स्तर और बुनियादी डिवाइस जाँचें (मॉक लोकेशन, रूटेड डिवाइस, घड़ी का अंतर) दर्ज करता है। विज़िट के दौरान ली गई फ़ोटो, नोट और किसान की पुष्टि भी दर्ज होती है।\n\n2. केवल ड्यूटी पर। लोकेशन तभी दर्ज होती है जब आप ड्यूटी चालू करते हैं; ड्यूटी बंद करते ही, संस्था के तय समय पर दिन समाप्त होने पर (डिफ़ॉल्ट 20:00) या घर पर 60 मिनट निष्क्रिय रहने पर यह रुक जाती है। ड्यूटी बंद होने पर कुछ भी दर्ज नहीं होता, और लोकेशन चालू रहने तक एक सूचना हमेशा दिखती है।\n\n3. हम इसे क्यों इकट्ठा करते हैं। आपके ट्रैक से यात्रा भत्ते के किलोमीटर की गणना होती है, और विज़िट पर आपकी लोकेशन से उस विज़िट का क्रेडिट मिलता है। ट्रैक नहीं तो स्वचालित यात्रा भत्ता नहीं और सत्यापित विज़िट नहीं।\n\n4. इसे कौन देख सकता है। आपके क्लस्टर हेड, निदेशक और संस्था के मालिक अपने क्षेत्र के लिए आपका ट्रैक और विज़िट देख सकते हैं, और ऑडिटर फ़्लैग की गई विज़िट की समीक्षा कर सकते हैं। स्टोर मैनेजर और किसान आपकी लोकेशन कभी नहीं देखते। कच्चे पॉइंट 180 दिन रखे जाते हैं और फिर दैनिक योग में बदल दिए जाते हैं।';

  @override
  String get permissionsTitle => 'मित्र को चाहिए ये अनुमतियाँ';

  @override
  String get permissionsIntro =>
      'मित्र इन्हें एक-एक करके माँगेगा। इन्हें बाद में सेटिंग्स में बदल सकते हैं।';

  @override
  String get permLocationTitle => 'लोकेशन';

  @override
  String get permLocationBody =>
      'ड्यूटी पर आपका ट्रैक दर्ज करने और यह जाँचने के लिए कि आप खेत पर हैं।';

  @override
  String get permBackgroundTitle => 'लोकेशन हर समय';

  @override
  String get permBackgroundBody =>
      '\"हर समय अनुमति दें\" चुनें ताकि स्क्रीन बंद होने पर भी ट्रैकिंग चलती रहे। फिर भी यह केवल ड्यूटी पर ही चलती है।';

  @override
  String get permCameraTitle => 'कैमरा';

  @override
  String get permCameraBody =>
      'ऐप के अंदर ली गई खेत और विज़िट की फ़ोटो के लिए।';

  @override
  String get permNotificationsTitle => 'सूचनाएँ';

  @override
  String get permNotificationsBody =>
      'ड्यूटी की सूचना दिखाने और ड्यूटी खत्म होने से पहले याद दिलाने के लिए।';

  @override
  String get permGranted => 'अनुमति दी गई';

  @override
  String get permDenied => 'अनुमति नहीं';

  @override
  String get permOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get permAllow => 'अनुमति दें';

  @override
  String get registeredTitle => 'डिवाइस पंजीकृत';

  @override
  String get registeredBody =>
      'आप तैयार हैं। दिन शुरू करने के लिए होम से ड्यूटी पर जाएँ।';

  @override
  String get registeredStart => 'होम पर जाएँ';

  @override
  String get homeTitle => 'होम';

  @override
  String get homeTodayStats => 'आज';

  @override
  String get statVisitsVerified => 'सत्यापित विज़िट';

  @override
  String get statFarmersAdded => 'जोड़े गए किसान';

  @override
  String get statCollections => 'वसूली';

  @override
  String get homeNextUp => 'अगला';

  @override
  String get homeNextUpEmpty => 'अभी कोई बीट प्लान नहीं';

  @override
  String get homeNextUpEmptyHelp =>
      'आपके क्लस्टर हेड गाँव सौंपेंगे। तब तक किसान जोड़ें और विज़िट शुरू करें।';

  @override
  String get homeQuickActions => 'त्वरित कार्य';

  @override
  String get actionStartVisit => 'विज़िट शुरू करें';

  @override
  String get actionScoutCrop => 'फ़सल जाँचें';

  @override
  String get actionCollectPayment => 'भुगतान लें';

  @override
  String get comingSoon => 'जल्द आ रहा है';

  @override
  String get navHome => 'होम';

  @override
  String get navFarmers => 'किसान';

  @override
  String get navVisits => 'विज़िट';

  @override
  String get navOrders => 'ऑर्डर';

  @override
  String get navMe => 'मैं';

  @override
  String get myDayTitle => 'मेरा दिन';

  @override
  String myDayKm(String km) {
    return 'आज $km कि.मी.';
  }

  @override
  String get myDayEmpty => 'आज अभी तक ड्यूटी नहीं';

  @override
  String get myDayEmptyHelp =>
      'होम से ड्यूटी पर जाएँ; आपका ट्रैक और कि.मी. यहाँ दिखेंगे।';

  @override
  String myDaySession(String start, String end) {
    return 'ड्यूटी $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return '$start से ड्यूटी पर';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending लंबित · $accepted स्वीकृत';
  }

  @override
  String get myDayGapsTitle => 'अंतराल और कारण';

  @override
  String get myDayGapsHelp => 'अंतराल के कारण अगले अपडेट के साथ आएँगे।';

  @override
  String get myDayEndReasonManual => 'आपने समाप्त किया';

  @override
  String get myDayEndReasonAutoTime => 'दिन के अंत में समाप्त';

  @override
  String get myDayEndReasonAutoIdle => 'निष्क्रियता के बाद समाप्त';

  @override
  String get myDayEndReasonForced => 'मैनेजर ने समाप्त किया';

  @override
  String get myDayEndReasonRejected => 'दर्ज नहीं हुई';

  @override
  String get syncEntityDutySession => 'ड्यूटी सत्र';

  @override
  String get syncEntityLocationBatch => 'लोकेशन पॉइंट';

  @override
  String get syncEntityPolicyAcceptance => 'नीति स्वीकृति';

  @override
  String get visitsTitle => 'भेंटें';

  @override
  String get visitsTabToday => 'आज';

  @override
  String get visitsTabWeek => 'इस सप्ताह';

  @override
  String get visitsFilterAll => 'सभी';

  @override
  String get visitsEmptyTitle => 'अभी तक कोई भेंट नहीं';

  @override
  String get visitsEmptyHelp =>
      'किसान प्रोफ़ाइल से या नीचे दिए बटन से भेंट शुरू करें।';

  @override
  String get visitStatusOpen => 'जारी है';

  @override
  String get visitCardPending => 'ऑनलाइन होने पर सिंक होगा';

  @override
  String get visitCardFailed => 'ध्यान देना ज़रूरी';

  @override
  String get visitChooseFarmer => 'किसान चुनें';

  @override
  String get visitFarmLabel => 'खेत';

  @override
  String get visitFarmNoBoundary => 'इस खेत की सीमा दर्ज नहीं है';

  @override
  String get visitPurposeLabel => 'उद्देश्य';

  @override
  String get visitOffDutyTitle => 'पहले ड्यूटी पर जाएँ';

  @override
  String get visitOffDutyBody =>
      'भेंटें केवल ड्यूटी पर होने पर दर्ज होती हैं। होम से ड्यूटी चालू करें और वापस आएँ।';

  @override
  String get visitGoHome => 'होम पर जाएँ';

  @override
  String get visitLocating => 'आपकी लोकेशन ली जा रही है…';

  @override
  String get visitNoFix =>
      'आपकी लोकेशन नहीं मिली। खुले आसमान के नीचे जाकर फिर कोशिश करें।';

  @override
  String get visitRefreshLocation => 'लोकेशन फिर जाँचें';

  @override
  String visitAccuracy(int metres) {
    return 'सटीकता ±$metres मी';
  }

  @override
  String get visitInsideGeofence => 'आप खेत की जियोफ़ेंस के अंदर हैं';

  @override
  String get visitAtMeetingPoint => 'आप गाँव के मीटिंग पॉइंट पर हैं';

  @override
  String visitOutsideFarm(int distance, int radius) {
    return 'खेत की सीमा से $distance मी दूर; जियोफ़ेंस $radius मी है।';
  }

  @override
  String visitOutsideMeeting(int distance, int radius) {
    return 'मीटिंग पॉइंट से $distance मी दूर; अनुमत दायरा $radius मी है।';
  }

  @override
  String get visitNoTarget =>
      'इस खेत की सीमा नहीं है और गाँव का मीटिंग पॉइंट नहीं है। ओवरराइड नोट के साथ चेक इन करें।';

  @override
  String get visitRequestOverride => 'ओवरराइड माँगें';

  @override
  String get visitOverrideNoteLabel => 'आप यहाँ से क्यों चेक इन कर रहे हैं?';

  @override
  String get visitOverrideNoteHint => 'जैसे: किसान से बाज़ार में मिला';

  @override
  String get visitOverrideNoteRequired => 'ओवरराइड माँगने के लिए नोट लिखें';

  @override
  String get visitOverrideHelp =>
      'आपका क्लस्टर हेड ओवरराइड की समीक्षा करेगा। मंज़ूरी मिलने पर ही भेंट को जियोफ़ेंस क्रेडिट मिलेगा।';

  @override
  String get visitCheckIn => 'चेक इन';

  @override
  String get visitCheckInOverride => 'ओवरराइड के साथ चेक इन';

  @override
  String get visitInProgress => 'भेंट जारी है';

  @override
  String get visitTimerLabel => 'भेंट का समय';

  @override
  String visitMinDuration(int minutes) {
    return 'न्यूनतम $minutes मिनट';
  }

  @override
  String visitDurationNeeds(int minutes, int minimum) {
    return '$minimum मिनट में से $minutes मिनट';
  }

  @override
  String visitUnderMinimum(int minutes) {
    return 'न्यूनतम $minutes मिनट से कम। भेंट फ़्लैग होगी, अस्वीकार नहीं।';
  }

  @override
  String get visitPhotos => 'फ़ोटो';

  @override
  String get visitTakePhoto => 'फ़ोटो लें';

  @override
  String visitPhotoCount(int count) {
    return '$count फ़ोटो';
  }

  @override
  String get visitPhotosHelp => 'केवल ऐप कैमरा। खेत पर कम से कम एक फ़ोटो लें।';

  @override
  String get visitNotesLabel => 'नोट्स';

  @override
  String get visitNotesHint => 'आपने क्या देखा या क्या सलाह दी?';

  @override
  String get visitVoiceInputSoon => 'वॉइस इनपुट अगले अपडेट में आएगा';

  @override
  String get visitCropStageLabel => 'फ़सल की अवस्था';

  @override
  String get cropStageSown => 'बुवाई';

  @override
  String get cropStageMaturity => 'पकाव';

  @override
  String get cropStageHarvested => 'कटाई हो गई';

  @override
  String get visitProofTitle => 'भेंट का प्रमाण';

  @override
  String get visitExpectedScore => 'अनुमानित स्कोर';

  @override
  String get visitServerScore => 'सर्वर से स्कोर';

  @override
  String get visitConfirmFarmer => 'किसान की पुष्टि';

  @override
  String get visitCheckOut => 'चेक आउट';

  @override
  String get visitCheckInPending => 'ऑनलाइन होने पर चेक इन सिंक होगा';

  @override
  String get visitCheckInSynced => 'चेक इन सिंक हो गया';

  @override
  String get visitRejectedTitle => 'चेक इन अस्वीकृत';

  @override
  String visitRejectedOutside(int distance) {
    return 'सर्वर ने आपको जियोफ़ेंस से $distance मी बाहर पाया।';
  }

  @override
  String get visitRejectedNoTarget =>
      'सर्वर को आपकी लोकेशन जाँचने के लिए कुछ नहीं मिला।';

  @override
  String get visitRetryFromFarm => 'खेत से फिर कोशिश करें';

  @override
  String visitRetryStillOutside(int distance) {
    return 'अभी भी $distance मी बाहर हैं। पास जाएँ या ओवरराइड माँगें।';
  }

  @override
  String get visitRetryQueued =>
      'आपकी मौजूदा लोकेशन के साथ चेक इन फिर कतार में है।';

  @override
  String get proofGeofenceOverride =>
      'ओवरराइड माँगा गया; क्लस्टर हेड की प्रतीक्षा';

  @override
  String get proofGeofenceOutside => 'जियोफ़ेंस के बाहर';

  @override
  String get proofPhotoDone => 'लोकेशन के साथ फ़ोटो ली गई';

  @override
  String get proofDurationDone => 'न्यूनतम अवधि पूरी हुई';

  @override
  String get proofIntegrityIssue =>
      'डिवाइस जाँच में समस्या; इस हिस्से का स्कोर 0';

  @override
  String get visitConfirmTitle => 'किसान की पुष्टि';

  @override
  String get visitConfirmIntro =>
      'किसान से इनमें से किसी एक तरीके से भेंट की पुष्टि कराएँ।';

  @override
  String get visitConfirmOtp => 'SMS से OTP';

  @override
  String get visitConfirmOtpHelp =>
      'किसान के फ़ोन पर कोड जाएगा; उसे यहाँ टाइप करें।';

  @override
  String get visitConfirmPush => 'किसान ऐप में पूछें';

  @override
  String get visitConfirmPushHelp => 'किसान अपने ऐप में पुष्टि करें दबाता है।';

  @override
  String get visitConfirmQr => 'QR दिखाएँ';

  @override
  String get visitConfirmQrHelp => 'किसान इसे किसान ऐप से स्कैन करता है।';

  @override
  String get visitConfirmNeedsNetwork =>
      'इसके लिए नेटवर्क चाहिए। ऑनलाइन होने पर फिर कोशिश करें।';

  @override
  String get visitConfirmQrNeedsSync =>
      'QR के लिए पहले एक बार सिंक ज़रूरी है। एक बार कनेक्ट करें और वापस आएँ।';

  @override
  String get visitConfirmNotSynced =>
      'चेक इन अभी सर्वर तक नहीं पहुँचा। सिंक करके फिर कोशिश करें।';

  @override
  String get visitConfirmQueued =>
      'अनुरोध सहेजा गया। ऑनलाइन होते ही किसान के ऐप में जाएगा।';

  @override
  String get visitConfirmWaiting => 'किसान की प्रतीक्षा…';

  @override
  String get visitConfirmWaitingPush =>
      'हमने किसान ऐप में किसान से पूछा है। पुष्टि होते ही यह स्क्रीन अपडेट होगी।';

  @override
  String get visitConfirmQrWaiting => 'किसान के स्कैन करने की प्रतीक्षा…';

  @override
  String get visitConfirmed => 'किसान ने पुष्टि की';

  @override
  String visitConfirmedVia(String channel) {
    return '$channel से पुष्टि हुई';
  }

  @override
  String visitConfirmOtpSent(String phone) {
    return '$phone पर कोड भेजा गया';
  }

  @override
  String get visitConfirmAlready => 'इस भेंट की पुष्टि पहले ही हो चुकी है।';

  @override
  String get visitConfirmRefused =>
      'अभी किसान से इस तरह नहीं पूछा जा सकता। दूसरा तरीका आज़माएँ।';

  @override
  String get visitConfirmContinue => 'चेक आउट पर जाएँ';

  @override
  String get visitConfirmLater => 'बाद में पुष्टि करें';

  @override
  String visitConfirmExpires(int minutes) {
    return '$minutes मिनट में समाप्त';
  }

  @override
  String get visitConfirmChooseAnother => 'दूसरा तरीका चुनें';

  @override
  String get visitSummaryTitle => 'चेक आउट सारांश';

  @override
  String get visitSummaryDuration => 'अवधि';

  @override
  String get visitSummaryMissing => 'क्या कमी रही';

  @override
  String get visitSummaryComplete => 'सब कुछ सही है';

  @override
  String get visitSummaryPending =>
      'अगले सिंक के बाद सर्वर स्कोर की पुष्टि करेगा';

  @override
  String get visitSummaryServer => 'सर्वर ने स्कोर की पुष्टि की';

  @override
  String get visitSummaryNotCheckedOut => 'यह भेंट अभी भी खुली है।';

  @override
  String get visitSummaryOverridePending => 'ओवरराइड समीक्षा की प्रतीक्षा में';

  @override
  String get visitDone => 'हो गया';

  @override
  String get syncEntityVisit => 'भेंट';

  @override
  String get syncEntityVisitPhoto => 'भेंट का फ़ोटो';

  @override
  String get syncEntityVisitConfirmation => 'किसान की पुष्टि';

  @override
  String get catalogTitle => 'उत्पाद';

  @override
  String catalogForFarmer(String name) {
    return '$name के लिए';
  }

  @override
  String get catalogSearchHint => 'नाम, ब्रांड या दवा का तत्व खोजें';

  @override
  String get catalogCategoryAll => 'सभी';

  @override
  String get catalogCategorySeed => 'बीज';

  @override
  String get catalogCategoryFertiliser => 'खाद';

  @override
  String get catalogCategoryPesticide => 'कीटनाशक';

  @override
  String get catalogCategoryFungicide => 'फफूंदनाशक';

  @override
  String get catalogCategoryHerbicide => 'खरपतवारनाशक';

  @override
  String get catalogCategoryGrowth => 'वृद्धि वर्धक';

  @override
  String get catalogCategoryTool => 'औज़ार';

  @override
  String get catalogCategoryOther => 'अन्य';

  @override
  String catalogAsOf(String time) {
    return '$time तक के दाम और स्टॉक';
  }

  @override
  String catalogStale(String time) {
    return 'दाम और स्टॉक पुराने हो सकते हैं ($time तक के)। इंटरनेट मिलने पर रीफ़्रेश करें।';
  }

  @override
  String get catalogNeverLoaded => 'उत्पाद सूची अभी इस फ़ोन पर नहीं है';

  @override
  String get catalogNeverLoadedHelp =>
      'उत्पाद और दाम डाउनलोड करने के लिए इंटरनेट से जुड़ें।';

  @override
  String get catalogRefresh => 'रीफ़्रेश करें';

  @override
  String get catalogRefreshFailed =>
      'रीफ़्रेश नहीं हो सका। सेव किए गए उत्पाद दिखा रहे हैं।';

  @override
  String get catalogEmpty => 'कोई उत्पाद नहीं मिला';

  @override
  String get catalogEmptyHelp => 'दूसरा नाम या श्रेणी आज़माएँ।';

  @override
  String get catalogStoreUnknown =>
      'दुकान अभी पता नहीं है। अगले सिंक के बाद स्टॉक दिखेगा।';

  @override
  String get productPriceEstimate => 'अनुमानित दाम';

  @override
  String productStockNearest(int count) {
    return 'पास के दुकान में $count स्टॉक में';
  }

  @override
  String productStockAsOf(String time) {
    return '$time तक';
  }

  @override
  String productInCart(int count) {
    return 'कार्ट में $count';
  }

  @override
  String get cartEstimatedTotal => 'अनुमानित कुल';

  @override
  String get cartViewCart => 'कार्ट देखें';

  @override
  String get cartTitle => 'कार्ट';

  @override
  String get cartEmpty => 'कार्ट खाली है';

  @override
  String get cartEmptyHelp => 'उत्पाद सूची से उत्पाद जोड़ें।';

  @override
  String get cartAddMore => 'और उत्पाद जोड़ें';

  @override
  String get cartSubtotal => 'उप-कुल (अनुमान)';

  @override
  String get cartTax => 'GST (अनुमान)';

  @override
  String get cartEstimateNote =>
      'दाम सेव की गई दर-सूची से अनुमान हैं। ऑर्डर सिंक होने पर दुकान अंतिम रकम तय करती है।';

  @override
  String get cartFulfilment => 'किसान को सामान कैसे मिलेगा?';

  @override
  String get fulfilmentPickup => 'दुकान से लेना';

  @override
  String get fulfilmentDelivery => 'होम डिलीवरी';

  @override
  String get cartChoosePayment => 'भुगतान चुनें';

  @override
  String get cartDecrease => 'एक कम करें';

  @override
  String get cartIncrease => 'एक बढ़ाएँ';

  @override
  String cartShortLine(String available, String requested) {
    return 'दुकान में सिर्फ़ $available उपलब्ध हैं ($requested माँगे)।';
  }

  @override
  String cartUseAvailable(String available) {
    return '$available रखें';
  }

  @override
  String get cartShortTitle =>
      'दुकान में कुछ सामान कम है। मात्रा बदलकर फिर भेजें।';

  @override
  String get checkoutTitle => 'भुगतान';

  @override
  String get checkoutOrderAmount => 'ऑर्डर कुल (अनुमान)';

  @override
  String get checkoutDuesAmount => 'वसूल की जाने वाली रकम (₹)';

  @override
  String checkoutDuesBalance(String amount) {
    return 'बकाया $amount';
  }

  @override
  String checkoutDuesTooMuch(String amount) {
    return '$amount तक की रकम डालें';
  }

  @override
  String get checkoutDuesInvalid => 'रकम डालें';

  @override
  String get checkoutPlaceOrder => 'ऑर्डर दें';

  @override
  String get checkoutCollect => 'वसूल करें';

  @override
  String get checkoutNeedsInternet => 'इंटरनेट चाहिए: नकद या उधार लें';

  @override
  String get checkoutCreditOrdersOnly => 'उधार सिर्फ़ ऑर्डर के लिए है';

  @override
  String checkoutCreditLeft(String amount) {
    return 'बची सीमा $amount';
  }

  @override
  String get checkoutOfflineNote =>
      'आप ऑफ़लाइन हैं। नकद और उधार फ़ोन में सेव होकर इंटरनेट मिलने पर भेजे जाएँगे।';

  @override
  String get checkoutOrderNotSynced =>
      'ऑर्डर अभी सर्वर तक नहीं पहुँचा। इंटरनेट मिलने पर फिर कोशिश करें या नकद लें।';

  @override
  String get checkoutNetworkError =>
      'सर्वर से संपर्क नहीं हुआ। इंटरनेट जाँचकर फिर कोशिश करें।';

  @override
  String get checkoutAlreadyPaid => 'इस ऑर्डर का भुगतान हो चुका है।';

  @override
  String get checkoutAmountMismatch =>
      'सर्वर पर रकम बदल गई है। ऑर्डर जाँचकर फिर कोशिश करें।';

  @override
  String get checkoutNothingDue => 'इस किसान का कुछ बकाया नहीं है।';

  @override
  String checkoutRefused(String code) {
    return 'भुगतान नहीं बन सका ($code)।';
  }

  @override
  String get paymentCard => 'कार्ड';

  @override
  String get paymentDone => 'हो गया';

  @override
  String get upiTitle => 'UPI QR';

  @override
  String get upiExpired => 'QR की समय-सीमा खत्म';

  @override
  String get upiCollectCash => 'इसके बजाय नकद लें';

  @override
  String get linkTitle => 'भुगतान लिंक';

  @override
  String get linkSentTitle => 'भुगतान लिंक भेज दिया';

  @override
  String linkSentVia(String channel) {
    return '$channel से भेजा। किसान से लिंक खोलकर भुगतान करने को कहें।';
  }

  @override
  String get channelSms => 'SMS';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get linkResend => 'लिंक फिर भेजें';

  @override
  String get linkResent => 'लिंक फिर भेज दिया';

  @override
  String get linkCheckStatus => 'भुगतान जाँचें';

  @override
  String linkValidUntil(String time) {
    return '$time तक मान्य';
  }

  @override
  String get cashTitle => 'नकद रसीद';

  @override
  String get cashAmount => 'लिया गया नकद';

  @override
  String get cashTakePhoto => 'रसीद की फ़ोटो लें';

  @override
  String get cashRetake => 'फिर से लें';

  @override
  String get cashSave => 'नकद भुगतान सेव करें';

  @override
  String get cashPhotoHelp =>
      'किसान को दी गई रसीद की फ़ोटो लें। सिर्फ़ ऐप का कैमरा इस्तेमाल होगा।';

  @override
  String get cashPhotoBad =>
      'फ़ोटो धुंधली या अँधेरी है। अच्छी रोशनी में फिर लें।';

  @override
  String get cashSaved => 'नकद सेव हुआ। दुकान के मिलान का इंतज़ार।';

  @override
  String get cashPendingReconciliation =>
      'दुकान मिलान बाकी: दुकान दिन के अंत में नकद जाँचेगी।';

  @override
  String get creditTitle => 'उधार बिक्री';

  @override
  String get creditQueued =>
      'फ़ोन में सेव हुआ। इंटरनेट मिलने पर उधार सीमा जाँची जाएगी।';

  @override
  String get creditApprovedTitle => 'किसान के खाते में जोड़ा गया';

  @override
  String get creditNeedsApprovalTitle => 'मंज़ूरी चाहिए';

  @override
  String get creditNeedsApprovalBody =>
      'यह बिक्री किसान की उधार सीमा से ज़्यादा है। मंज़ूरी के लिए क्लस्टर हेड को भेजी गई।';

  @override
  String get creditLimit => 'उधार सीमा';

  @override
  String get creditBalance => 'अभी का बकाया';

  @override
  String get creditShortfall => 'सीमा से ज़्यादा';

  @override
  String get creditSentToClusterHead => 'क्लस्टर हेड को भेजा';

  @override
  String get creditCheckAgain => 'मंज़ूरी जाँचें';

  @override
  String get creditStillPending => 'अभी मंज़ूरी नहीं मिली। बाद में फिर जाँचें।';

  @override
  String get creditOfflineCheck => 'मंज़ूरी जाँचने के लिए इंटरनेट से जुड़ें।';

  @override
  String get creditUseCash => 'इसके बजाय नकद लें';

  @override
  String get orderTitle => 'ऑर्डर';

  @override
  String get orderPlacedTitle => 'ऑर्डर दिया गया';

  @override
  String get orderQueuedTitle => 'ऑर्डर सेव हुआ, सिंक का इंतज़ार';

  @override
  String get orderQueuedHelp => 'फ़ोन पर इंटरनेट आते ही यह दुकान को जाएगा।';

  @override
  String get orderRejectedTitle => 'दुकान यह ऑर्डर नहीं ले सकी';

  @override
  String get orderInsufficientStock => 'दुकान में कुछ सामान कम है:';

  @override
  String orderShortLine(String product, String available, String requested) {
    return '$product: $available उपलब्ध, $requested माँगे';
  }

  @override
  String get orderSkuNotRecommendable =>
      'एक उत्पाद इस फ़सल और कीट के लिए स्वीकृत नहीं है (लेबल दावा)। उसे हटाकर फिर भेजें।';

  @override
  String get orderEditAndResend => 'बदलकर फिर भेजें';

  @override
  String get orderSummary => 'सारांश';

  @override
  String get orderSubtotal => 'उप-कुल';

  @override
  String get orderTax => 'GST';

  @override
  String get orderTotal => 'कुल';

  @override
  String get orderTotalEstimate => 'कुल (अनुमान)';

  @override
  String get orderStatusTitle => 'स्थिति';

  @override
  String get orderStatusPlaced => 'ऑर्डर दिया';

  @override
  String get orderStatusReserved => 'स्टॉक रोका गया';

  @override
  String get orderStatusPacked => 'पैक हुआ';

  @override
  String get orderStatusReady => 'तैयार';

  @override
  String get orderStatusHandedOver => 'सौंप दिया';

  @override
  String get orderStatusDelivered => 'पहुँचा दिया';

  @override
  String get orderStatusCancelled => 'रद्द';

  @override
  String get orderPayments => 'भुगतान';

  @override
  String get orderNoPayments => 'अभी कोई भुगतान नहीं';

  @override
  String get orderShareInvoice => 'WhatsApp पर बिल भेजें';

  @override
  String get orderShareOffline => 'बिल भेजने के लिए इंटरनेट से जुड़ें।';

  @override
  String get orderShareNoInvoice => 'दुकान ऑर्डर सौंपते समय बिल बनाती है।';

  @override
  String get orderShareFailed => 'बिल का लिंक नहीं मिला। फिर कोशिश करें।';

  @override
  String orderShareText(String number, String url) {
    return 'बिल $number: $url';
  }

  @override
  String orderInvoiceNo(String number) {
    return 'बिल $number';
  }

  @override
  String get orderCollectPayment => 'भुगतान लें';

  @override
  String get orderPendingSync => 'सिंक का इंतज़ार';

  @override
  String get orderRejected => 'ध्यान दें';

  @override
  String get ordersTitle => 'ऑर्डर';

  @override
  String get ordersEmpty => 'अभी कोई ऑर्डर नहीं';

  @override
  String get ordersEmptyHelp => 'किसानों के लिए दिए गए ऑर्डर यहाँ दिखेंगे।';

  @override
  String get ordersNew => 'नया ऑर्डर';

  @override
  String get ordersCollections => 'वसूली';

  @override
  String get ordersPickFarmer => 'किसान चुनें';

  @override
  String get khataTitle => 'खाता';

  @override
  String khataAsOf(String time) {
    return '$time तक';
  }

  @override
  String khataOfflineAsOf(String time) {
    return 'ऑफ़लाइन: $time पर सेव किया खाता दिखा रहे हैं';
  }

  @override
  String get khataNotLoaded => 'खाता अभी इस फ़ोन पर नहीं है';

  @override
  String get khataNotLoadedHelp =>
      'किसान का खाता लाने के लिए इंटरनेट से जुड़ें।';

  @override
  String khataOverdue(String amount) {
    return 'बकाया समय पार $amount';
  }

  @override
  String get khataBucket0to30 => '0–30 दिन';

  @override
  String get khataBucket31to60 => '31–60 दिन';

  @override
  String get khataBucket61to90 => '61–90 दिन';

  @override
  String get khataBucket90plus => '90+ दिन';

  @override
  String khataDueHarvest(String date, String month) {
    return 'देय $date · फ़सल $month';
  }

  @override
  String get khataEntryOrder => 'उधार बिक्री';

  @override
  String get khataEntryPayment => 'भुगतान मिला';

  @override
  String get khataEntryAdjustment => 'समायोजन';

  @override
  String get khataPaymentHistory => 'भुगतान इतिहास';

  @override
  String get khataNoPayments => 'अभी कोई भुगतान नहीं';

  @override
  String get khataPendingCollections => 'वसूल हुआ, अभी खाते में नहीं';

  @override
  String get collectionsTitle => 'वसूली';

  @override
  String get collectionsToday => 'आज';

  @override
  String get collectionsWeek => 'इस हफ़्ते';

  @override
  String get collectionsTotal => 'कुल वसूली';

  @override
  String get collectionsEmpty => 'अभी कोई वसूली नहीं';

  @override
  String get collectionsEmptyHelp => 'आपकी वसूली यहाँ दिखेगी।';

  @override
  String get collectionStateWaitingToSync => 'सिंक का इंतज़ार';

  @override
  String get collectionStatePendingReconciliation => 'मिलान बाकी';

  @override
  String get collectionStateWaiting => 'भुगतान का इंतज़ार';

  @override
  String get collectionStatePaid => 'भुगतान हुआ';

  @override
  String get collectionStateOnKhata => 'खाते में';

  @override
  String get collectionStateApprovalNeeded => 'मंज़ूरी चाहिए';

  @override
  String get collectionStateFailed => 'विफल';

  @override
  String get syncEntityOrder => 'ऑर्डर';

  @override
  String get syncEntityPayment => 'भुगतान';

  @override
  String get storeModeTitle => 'स्टोर मोड';

  @override
  String get storeSettingsEntryHint => 'बिक्री, ऑर्डर, स्टॉक और दिन की समाप्ति';

  @override
  String get storeNavHome => 'होम';

  @override
  String get storeNavPos => 'बेचें';

  @override
  String get storeNavQueue => 'ऑर्डर';

  @override
  String get storeNavStock => 'स्टॉक';

  @override
  String get storeNavCredit => 'उधार';

  @override
  String get storeNavDayClose => 'दिन की समाप्ति';

  @override
  String get storeReadOnlyBanner =>
      'आप यह स्टोर देख रहे हैं। बदलाव केवल स्टोर टीम कर सकती है।';

  @override
  String get storeNotAllowedTitle => 'स्टोर मोड उपलब्ध नहीं है';

  @override
  String get storeNotAllowedHelp =>
      'स्टोर मोड स्टोर मैनेजर, अकाउंटेंट और क्लस्टर हेड के लिए है।';

  @override
  String get storeOfflineTitle => 'आप ऑफ़लाइन हैं';

  @override
  String get storeOfflineHelp =>
      'स्टोर मोड को नेटवर्क चाहिए। कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get storeErrorTitle => 'लोड नहीं हो सका';

  @override
  String get storeErrorHelp => 'कुछ गलत हुआ। फिर कोशिश करें।';

  @override
  String get storeSwitchStore => 'स्टोर बदलें';

  @override
  String get storeHomeTitle => 'स्टोर होम';

  @override
  String get storeTodaySales => 'आज की बिक्री';

  @override
  String storeSalesCount(int count) {
    return 'भुगतान: $count';
  }

  @override
  String get storeModeUpi => 'UPI QR';

  @override
  String get storeModeCard => 'कार्ड';

  @override
  String get storeModeCash => 'नकद';

  @override
  String get storeModeCredit => 'उधार (खाता)';

  @override
  String get storeQueueCounts => 'ऑर्डर कतार';

  @override
  String get storeTabNew => 'नए';

  @override
  String get storeTabPacking => 'पैकिंग';

  @override
  String get storeTabReady => 'तैयार';

  @override
  String get storeTabHandedOver => 'सौंपे गए';

  @override
  String storeTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get storeLowStock => 'कम स्टॉक';

  @override
  String storeLowStockCount(int count) {
    return 'कम वाले आइटम: $count';
  }

  @override
  String storeExpiringCount(int count) {
    return 'जल्द समाप्त होने वाले: $count';
  }

  @override
  String get storeDayCloseStatus => 'दिन की समाप्ति';

  @override
  String get storeDayOpen => 'खुला है, अभी बंद नहीं हुआ';

  @override
  String storeDayClosed(String time) {
    return '$time पर बंद हुआ';
  }

  @override
  String get storeDayReopened => 'फिर से खोला गया';

  @override
  String get storeActionNewSale => 'नई बिक्री';

  @override
  String get storeActionReceive => 'माल प्राप्ति';

  @override
  String get storeActionTransfer => 'स्टॉक ट्रांसफ़र';

  @override
  String get storeActionCloseDay => 'दिन बंद करें';

  @override
  String get storePosTitle => 'बिक्री काउंटर';

  @override
  String get storeSearchProducts => 'उत्पाद खोजें';

  @override
  String get storeScan => 'स्कैन';

  @override
  String get storeEnterCode => 'कोड डालें';

  @override
  String get storeCodeHint => 'बारकोड नंबर';

  @override
  String get storeCodeAdd => 'जोड़ें';

  @override
  String storeScanAdded(String name) {
    return '$name जोड़ा गया';
  }

  @override
  String storeScanNotFound(String code) {
    return 'कोड $code का कोई उत्पाद नहीं';
  }

  @override
  String get storeScanOffline => 'ऑफ़लाइन: कोड नहीं खोजा जा सकता';

  @override
  String get storeCategoryAll => 'सभी';

  @override
  String get storeCategorySeed => 'बीज';

  @override
  String get storeCategoryFertiliser => 'उर्वरक';

  @override
  String get storeCategoryPesticide => 'कीटनाशक';

  @override
  String get storeCategoryFungicide => 'फफूंदनाशक';

  @override
  String get storeCategoryHerbicide => 'खरपतवारनाशक';

  @override
  String get storeCategoryGrowth => 'वृद्धि वर्धक';

  @override
  String get storeCategoryTool => 'औज़ार';

  @override
  String get storeCategoryOther => 'अन्य';

  @override
  String get storeCartTitle => 'कार्ट';

  @override
  String get storeCartEmpty => 'कार्ट खाली है';

  @override
  String get storeCartEmptyHelp =>
      'जोड़ने के लिए बारकोड स्कैन करें या उत्पाद पर टैप करें।';

  @override
  String get storeQtyDecrease => 'घटाएँ';

  @override
  String get storeQtyIncrease => 'बढ़ाएँ';

  @override
  String get storeSubtotal => 'उप-योग (GST से पहले)';

  @override
  String get storeGst => 'GST';

  @override
  String get storeTotal => 'कुल';

  @override
  String get storeRoundOff => 'राउंड ऑफ़';

  @override
  String get storeBuyerPhone => 'किसान का फ़ोन';

  @override
  String get storeBuyerFind => 'खोजें';

  @override
  String get storeBuyerWalkIn => 'सीधे आए ग्राहक के लिए खाली छोड़ें';

  @override
  String get storeBuyerUnknown => 'नया नंबर: बिक्री इस फ़ोन के नाम दर्ज होगी';

  @override
  String get storeBuyerClear => 'हटाएँ';

  @override
  String get storeNoProducts => 'कोई मेल खाता उत्पाद नहीं';

  @override
  String get storeCheckoutTitle => 'भुगतान';

  @override
  String get storePayWith => 'भुगतान का तरीका';

  @override
  String get storeModeUpiHint => 'किसान QR स्कैन करेंगे';

  @override
  String get storeModeCardHint => 'स्टोर टर्मिनल पर कार्ड';

  @override
  String get storeModeCashHint => 'नकद गिनें, छुट्टा दें';

  @override
  String get storeModeCreditHint => 'किसान के खाते में जोड़ें';

  @override
  String get storeCardReference => 'टर्मिनल संदर्भ';

  @override
  String get storeCardReferenceHint => 'पर्ची पर स्वीकृति कोड';

  @override
  String get storeCardReferenceRequired => 'टर्मिनल संदर्भ डालें';

  @override
  String get storeCashTendered => 'मिला नकद';

  @override
  String get storeCashChange => 'लौटाने के पैसे';

  @override
  String get storeCashShort => 'मिला नकद कुल से कम है';

  @override
  String get storeCreditNeedsFarmer =>
      'उधार के लिए पंजीकृत किसान चाहिए। फ़ोन से किसान खोजें।';

  @override
  String get storeInvoicePreview => 'GST इनवॉइस पूर्वावलोकन';

  @override
  String get storeInvoicePreviewNote =>
      'पुष्टि करने पर इनवॉइस नंबर और अंतिम टैक्स सर्वर से आते हैं।';

  @override
  String get storeColItem => 'आइटम';

  @override
  String get storeColHsn => 'HSN';

  @override
  String get storeColQty => 'मात्रा';

  @override
  String get storeColRate => 'दर';

  @override
  String get storeColGst => 'GST';

  @override
  String get storeColAmount => 'राशि';

  @override
  String get storeTaxable => 'कर योग्य मूल्य';

  @override
  String get storeCgst => 'CGST';

  @override
  String get storeSgst => 'SGST';

  @override
  String get storeIgst => 'IGST';

  @override
  String get storeConfirmSale => 'बिक्री की पुष्टि करें';

  @override
  String get storeOfflineSaleTitle => 'ऑफ़लाइन: बिक्री पूरी नहीं हो सकती';

  @override
  String get storeOfflineSaleHelp =>
      'कार्ट सुरक्षित है। नेटवर्क से जुड़ें और फिर पुष्टि करें।';

  @override
  String get storeApprovalNeededTitle => 'उधार की मंज़ूरी चाहिए';

  @override
  String storeApprovalNeededHelp(String amount) {
    return 'यह बिक्री किसान की सीमा से $amount ज़्यादा है। क्लस्टर हेड को मंज़ूरी देनी होगी। कार्ट सुरक्षित है।';
  }

  @override
  String get storeCreditBalance => 'खाता बकाया';

  @override
  String get storeCreditLimit => 'उधार सीमा';

  @override
  String get storeChooseAnotherMode => 'दूसरा तरीका चुनें';

  @override
  String get storeSaleFailedTitle => 'बिक्री पूरी नहीं हुई';

  @override
  String storeSaleFailed(String code) {
    return 'सर्वर ने बिक्री अस्वीकार की ($code)। कार्ट सुरक्षित है।';
  }

  @override
  String get storeInvoiceTitle => 'टैक्स इनवॉइस';

  @override
  String storeInvoiceNo(String number) {
    return 'इनवॉइस $number';
  }

  @override
  String get storeInvoicePaid => 'बिक्री पूरी हुई';

  @override
  String get storeInvoiceBuyer => 'बिल किसके नाम';

  @override
  String storeGstin(String gstin) {
    return 'GSTIN $gstin';
  }

  @override
  String get storeAmountInWords => 'राशि शब्दों में';

  @override
  String get storeOpenPdf => 'PDF खोलें';

  @override
  String get storeShareWhatsApp => 'WhatsApp पर भेजें';

  @override
  String get storeShareOther => 'शेयर करें';

  @override
  String storeShareSent(String to) {
    return '$to को भेजा गया';
  }

  @override
  String get storeShareFailed => 'भेजा नहीं जा सका। फिर कोशिश करें।';

  @override
  String get storePdfFailed => 'PDF नहीं खुल सका।';

  @override
  String storeShareText(String number, String amount, String url) {
    return 'इनवॉइस $number, राशि $amount: $url';
  }

  @override
  String get storeNextSale => 'अगली बिक्री';

  @override
  String get storeQueueTitle => 'ऑर्डर कतार';

  @override
  String storeOrderRef(String ref) {
    return 'ऑर्डर #$ref';
  }

  @override
  String get storeChannelOfficer => 'फ़ील्ड ऑफ़िसर';

  @override
  String get storeChannelFarmerApp => 'किसान ऐप';

  @override
  String get storeChannelPos => 'काउंटर';

  @override
  String get storeFulfilmentPickup => 'स्टोर से लेना';

  @override
  String get storeFulfilmentDelivery => 'डिलीवरी';

  @override
  String get storeStatusPlaced => 'ऑर्डर हुआ';

  @override
  String get storeStatusReserved => 'स्टॉक आरक्षित';

  @override
  String get storeStatusPacked => 'पैक हुआ';

  @override
  String get storeStatusReady => 'तैयार';

  @override
  String get storeStatusHandedOver => 'सौंप दिया';

  @override
  String get storeStatusDelivered => 'डिलीवर हुआ';

  @override
  String get storeStatusCancelled => 'रद्द';

  @override
  String get storeActionReserve => 'स्टॉक आरक्षित करें';

  @override
  String get storeActionPack => 'पैक हुआ चिह्नित करें';

  @override
  String get storeActionReady => 'तैयार चिह्नित करें';

  @override
  String get storeActionHandOver => 'सौंपें';

  @override
  String get storeActionDeliver => 'डिलीवर हुआ चिह्नित करें';

  @override
  String get storeActionCancel => 'ऑर्डर रद्द करें';

  @override
  String get storeCancelReason => 'रद्द करने का कारण';

  @override
  String get storeKeepOrder => 'ऑर्डर रखें';

  @override
  String get storeTransitionFailed =>
      'यह बदलाव अभी अनुमत नहीं है। सूची ताज़ा की गई।';

  @override
  String get storeQueueEmpty => 'यहाँ कोई ऑर्डर नहीं';

  @override
  String get storeQueueEmptyHelp =>
      'फ़ील्ड ऑफ़िसर और किसान ऐप के ऑर्डर यहाँ दिखते हैं।';

  @override
  String get storeSelectOrder => 'विवरण देखने के लिए ऑर्डर चुनें';

  @override
  String storeFarmerUnknown(String ref) {
    return 'किसान $ref';
  }

  @override
  String storeOrderMoved(String status) {
    return 'ऑर्डर अब: $status';
  }

  @override
  String get storeStockTitle => 'स्टॉक';

  @override
  String get storeOnHand => 'मौजूद';

  @override
  String get storeReserved => 'आरक्षित';

  @override
  String get storeAvailable => 'उपलब्ध';

  @override
  String storeBatch(String number) {
    return 'बैच $number';
  }

  @override
  String storeExpires(String date) {
    return 'समाप्ति $date';
  }

  @override
  String get storeNoExpiry => 'कोई समाप्ति नहीं';

  @override
  String get storeExpired => 'समाप्त';

  @override
  String get storeExpiring30 => '30 दिनों में समाप्ति';

  @override
  String get storeExpiring60 => '60 दिनों में समाप्ति';

  @override
  String get storeFilterLow => 'कम स्टॉक';

  @override
  String get storeFilterExpiring => 'समाप्ति के पास';

  @override
  String get storeStockEmpty => 'कोई मेल खाता स्टॉक नहीं';

  @override
  String get storeStockEmptyHelp => 'फ़िल्टर बदलें या माल प्राप्त करें।';

  @override
  String get storeSelectSku => 'बैच देखने के लिए आइटम चुनें';

  @override
  String get storeWriteOff => 'बट्टे खाते डालें';

  @override
  String get storeWriteOffTitle => 'स्टॉक बट्टे खाते में डालें';

  @override
  String get storeAdjust => 'गिनती सुधारें';

  @override
  String get storeAdjustTitle => 'गिने गए स्टॉक के अनुसार सुधारें';

  @override
  String get storeCountedQty => 'गिनी गई मात्रा';

  @override
  String get storeAdjustReasonHint => 'गिनती अलग क्यों है';

  @override
  String get storeReason => 'कारण';

  @override
  String get storeReasonRequired => 'कारण डालें';

  @override
  String get storeReasonDamage => 'क्षतिग्रस्त';

  @override
  String get storeReasonExpiry => 'समाप्त';

  @override
  String get storeReasonOther => 'अन्य';

  @override
  String get storeQuantity => 'मात्रा';

  @override
  String get storeQtyRequired => 'शून्य से ज़्यादा मात्रा डालें';

  @override
  String storeQtyTooHigh(String qty) {
    return 'उपलब्ध से ज़्यादा ($qty)';
  }

  @override
  String storeAvailableQty(String qty) {
    return 'उपलब्ध: $qty';
  }

  @override
  String get storeAddPhoto => 'फ़ोटो जोड़ें';

  @override
  String get storePhotoAdded => 'फ़ोटो जोड़ी गई';

  @override
  String get storeNote => 'नोट';

  @override
  String get storeSubmit => 'सेव करें';

  @override
  String get storeSaved => 'सेव हो गया';

  @override
  String get storeNegativeStock => 'बिना आरक्षित स्टॉक पर्याप्त नहीं';

  @override
  String get storeReceiptTitle => 'माल प्राप्ति';

  @override
  String get storeReference => 'आपूर्तिकर्ता इनवॉइस / संदर्भ';

  @override
  String get storeSku => 'आइटम';

  @override
  String get storeFindSku => 'आइटम (चुनें या स्कैन करें)';

  @override
  String get storeSkuRequired => 'आइटम चुनें';

  @override
  String get storeBatchNo => 'बैच नंबर';

  @override
  String get storeBatchNoRequired => 'बैच नंबर डालें';

  @override
  String get storeExpiryDate => 'समाप्ति तिथि';

  @override
  String get storeExpiryPast => 'समाप्ति तिथि बीत चुकी है';

  @override
  String get storeUnitCost => 'इकाई लागत (₹)';

  @override
  String get storeCostRequired => 'लागत डालें';

  @override
  String get storeAddLine => 'पंक्ति जोड़ें';

  @override
  String get storeRemoveLine => 'पंक्ति हटाएँ';

  @override
  String get storeReceiptSubmit => 'स्टॉक प्राप्त करें';

  @override
  String get storeReceiptDone => 'स्टॉक प्राप्त हुआ';

  @override
  String storeReceiptDoneHelp(int lines, String qty) {
    return 'पंक्तियाँ: $lines · जोड़ी गई इकाइयाँ: $qty';
  }

  @override
  String get storeBatchMismatch =>
      'यह बैच दूसरी समाप्ति तिथि के साथ पहले से है';

  @override
  String get storeTransferTitle => 'स्टॉक ट्रांसफ़र';

  @override
  String get storeToStore => 'किस स्टोर को';

  @override
  String get storeToStoreRequired => 'गंतव्य स्टोर चुनें';

  @override
  String get storeNoOtherStores =>
      'आपके लिए कोई दूसरा स्टोर उपलब्ध नहीं। अपने क्लस्टर हेड से पूछें।';

  @override
  String get storeChooseBatch => 'बैच';

  @override
  String get storeFefoSuggested => 'पहले समाप्त होने वाला पहले (सुझाव)';

  @override
  String get storeTransferSubmit => 'ट्रांसफ़र करें';

  @override
  String get storeTransferDone => 'ट्रांसफ़र पूरा हुआ';

  @override
  String get storeCreditTitle => 'उधार';

  @override
  String get storeApprovalsEmpty => 'कोई लंबित मंज़ूरी नहीं';

  @override
  String get storeApprovalAmount => 'बिक्री राशि';

  @override
  String get storeShortfall => 'सीमा से ज़्यादा';

  @override
  String get storeApprove => 'मंज़ूर करें';

  @override
  String get storeReject => 'अस्वीकार करें';

  @override
  String get storeDecisionNote => 'नोट (वैकल्पिक)';

  @override
  String get storeApproved => 'मंज़ूर। स्टोर एक बार बिक्री पूरी कर सकता है।';

  @override
  String get storeRejected => 'अस्वीकार किया';

  @override
  String get storeApprovalGone => 'इस अनुरोध पर पहले ही निर्णय हो चुका है';

  @override
  String get storeSetLimitTitle => 'किसान की उधार सीमा तय करें';

  @override
  String get storeLimitAmount => 'सीमा (₹)';

  @override
  String get storeLimitAmountRequired => 'सीमा रुपये में डालें';

  @override
  String get storeSetLimit => 'सीमा सेव करें';

  @override
  String storeLimitSaved(String amount) {
    return 'सीमा सेव हुई: $amount';
  }

  @override
  String storeLimitNeedsClusterHead(String cap) {
    return '$cap से ज़्यादा सीमा के लिए क्लस्टर हेड चाहिए। यह सीमा तय करने के लिए अपने क्लस्टर हेड से कहें।';
  }

  @override
  String get storeLimitFarmerNotFound =>
      'इस फ़ोन वाला किसान इस टैबलेट पर नहीं है';

  @override
  String storeManagerCapHint(String cap) {
    return 'आप $cap तक तय कर सकते हैं';
  }

  @override
  String get storeDayCloseTitle => 'दिन की समाप्ति';

  @override
  String get storeCashCount => 'नकद गिनती';

  @override
  String get storeCoins => 'सिक्के (₹)';

  @override
  String get storeExpectedCash => 'अपेक्षित नकद';

  @override
  String get storeCountedCash => 'गिना गया नकद';

  @override
  String get storeVariance => 'अंतर';

  @override
  String storeVarianceOver(String threshold) {
    return 'अंतर $threshold से ज़्यादा है: ऑडिटर को सूचना जाएगी';
  }

  @override
  String get storeDepositSlip => 'बैंक जमा पर्ची की फ़ोटो';

  @override
  String get storeTakePhoto => 'फ़ोटो लें';

  @override
  String get storeRetakePhoto => 'फिर से फ़ोटो लें';

  @override
  String get storeSlipRequired => 'जमा पर्ची की फ़ोटो लें';

  @override
  String get storeCloseNotes => 'नोट्स';

  @override
  String get storeCloseDay => 'दिन बंद करें';

  @override
  String get storeDayClosedTitle => 'दिन बंद हुआ';

  @override
  String get storeDayAlreadyClosed =>
      'आज पहले ही बंद हो चुका है। क्लस्टर हेड इसे फिर से खोल सकते हैं।';

  @override
  String get storeFlagged => 'ऑडिट के लिए चिह्नित';
}

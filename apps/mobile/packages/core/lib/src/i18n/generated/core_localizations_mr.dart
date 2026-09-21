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
  String get syncSyncing => 'सिंक होत आहे…';

  @override
  String get syncDetailsTitle => 'सिंक तपशील';

  @override
  String get syncNow => 'आता सिंक करा';

  @override
  String syncLastSync(String time) {
    return 'शेवटचे सिंक $time';
  }

  @override
  String get syncNeverSynced => 'अजून सिंक झाले नाही';

  @override
  String get syncAllDone => 'सर्व काही सिंक झाले';

  @override
  String get syncAllDoneHelp =>
      'ऑफलाइन जतन केलेले नवीन शेतकरी, शेते आणि फोटो सर्व्हरवर पोहोचेपर्यंत येथे दिसतील.';

  @override
  String syncPendingSection(int count) {
    return 'सिंकची वाट पाहत आहेत ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'लक्ष देणे आवश्यक ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'फोटो अपलोडची वाट पाहत आहे';

  @override
  String syncPhotoUploads(int count) {
    return 'अपलोड होत असलेले फोटो: $count';
  }

  @override
  String get syncTransportError =>
      'सर्व्हरशी संपर्क होऊ शकला नाही. ते आपोआप पुन्हा प्रयत्न करेल.';

  @override
  String syncNextAttempt(String time) {
    return 'पुढील प्रयत्न $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'नवीन';

  @override
  String get syncActionUpdate => 'संपादित';

  @override
  String get syncActionDelete => 'हटवलेले';

  @override
  String get syncEntityFarmer => 'शेतकरी';

  @override
  String get syncEntityFarm => 'शेत';

  @override
  String get syncEntityCropPlot => 'पीक प्लॉट';

  @override
  String get syncEntityConsent => 'संमती';

  @override
  String get syncEntityOther => 'आयटम';

  @override
  String syncSavedAt(String time) {
    return 'जतन केले $time';
  }

  @override
  String get syncRejectedDefault =>
      'सर्व्हरने हा आयटम स्वीकारला नाही. तो संपादित करून पुन्हा प्रयत्न करा.';

  @override
  String get syncRetryAll => 'सर्व पुन्हा प्रयत्न करा';

  @override
  String get syncDiscard => 'टाकून द्या';

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
  String get photoReviewHeading => 'तुमचा फोटो तपासा';

  @override
  String photoReviewTitle(int index, int total) {
    return 'फोटो $index / $total';
  }

  @override
  String get photoQualityOk => 'चांगला फोटो';

  @override
  String get photoQualityBlurry => 'अस्पष्ट आहे';

  @override
  String get photoQualityDark => 'खूप अंधार आहे';

  @override
  String get photoQualityChecking => 'फोटो तपासत आहोत';

  @override
  String get photoTipBlurry =>
      'फोन स्थिर धरा, पानावर टॅप करून फोकस करा आणि पुन्हा काढा';

  @override
  String get photoTipDark =>
      'चांगल्या उजेडात जा, सावलीतून बाहेर या आणि पुन्हा काढा';

  @override
  String get photoTipOk => 'फोटो चांगला आहे';

  @override
  String get photoRetake => 'पुन्हा काढा';

  @override
  String get photoUse => 'हा फोटो वापरा';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

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

  @override
  String get farmersTitle => 'शेतकरी';

  @override
  String get farmersSearchHint => 'नाव, फोन किंवा गाव शोधा';

  @override
  String get farmersAddFarmer => 'शेतकरी जोडा';

  @override
  String get farmersEmptyTitle => 'अजून शेतकरी नाहीत';

  @override
  String get farmersEmptyHelp =>
      'भेटी आणि ऑर्डर सुरू करण्यासाठी पहिला शेतकरी जोडा.';

  @override
  String get farmersNoResults => 'तुमच्या शोधाशी जुळणारे शेतकरी नाहीत';

  @override
  String get farmersFilterVillage => 'गाव';

  @override
  String get farmersFilterCrop => 'पीक';

  @override
  String get farmersFilterAll => 'सर्व';

  @override
  String farmersCount(int count) {
    return '$count शेतकरी';
  }

  @override
  String get farmerPendingSync => 'ऑनलाइन झाल्यावर सिंक होईल';

  @override
  String get farmerPhoneUnverified => 'फोन पडताळलेला नाही';

  @override
  String get farmerRejected => 'लक्ष द्या';

  @override
  String get regTitle => 'शेतकरी जोडा';

  @override
  String get regStepBasics => 'शेतकऱ्याचा तपशील';

  @override
  String get regStepBoundary => 'शेताची हद्द';

  @override
  String get regStepCrops => 'पिके';

  @override
  String get regStepConsent => 'संमती';

  @override
  String get regStepReview => 'तपासा आणि जतन करा';

  @override
  String get regResumeDraft => 'जिथे थांबला होता तिथून पुढे';

  @override
  String get regDiscardDraft => 'मसुदा काढून टाका';

  @override
  String get regFixIssues => 'पुढे जाण्यासाठी अधोरेखित फील्ड दुरुस्त करा';

  @override
  String get regNameLabel => 'शेतकऱ्याचे नाव';

  @override
  String get regNameHint => 'ओळखपत्रावर आहे तसे';

  @override
  String get regPhoneLabel => 'शेतकऱ्याचा मोबाइल नंबर';

  @override
  String get regPhoneHelper => 'शेतकऱ्याला OTP पाठवला जाईल';

  @override
  String get regSendOtpToFarmer => 'शेतकऱ्याला OTP पाठवा';

  @override
  String get regOtpSent => 'शेतकऱ्याला OTP पाठवला. त्यांना कोड विचारा.';

  @override
  String get regPhoneVerified => 'फोन पडताळला';

  @override
  String get regVerifyLater => 'नंतर पडताळा';

  @override
  String get regVerifyLaterNote =>
      'सिग्नल नाही? आता जतन करा आणि शेतकरी प्रोफाइलमधून फोन पडताळा.';

  @override
  String get regVerifyLaterChosen => 'नंतर पडताळला जाईल';

  @override
  String get regDuplicatePhone => 'या नंबरचा शेतकरी आधीच आहे';

  @override
  String get regDuplicateOpen => 'असलेला शेतकरी उघडा';

  @override
  String get regVillageLabel => 'गाव';

  @override
  String get regVillageHint => 'गाव निवडा';

  @override
  String get regVillageTyped => 'गावाचे नाव';

  @override
  String get regVillageNoneSynced =>
      'पहिल्या सिंकनंतर गावे लोड होतील. सध्या गावाचे नाव टाइप करा.';

  @override
  String get regLandmarkLabel => 'खूण';

  @override
  String get regLandmarkHint => 'मंदिर, शाळेजवळ…';

  @override
  String get regLanguageLabel => 'शेतकऱ्याची भाषा';

  @override
  String get regOwnershipLabel => 'जमीन';

  @override
  String get regBoundaryWalk => 'भोवती चाला';

  @override
  String get regBoundaryTap => 'कोपरे टॅप करा';

  @override
  String get regStartWalk => 'चालायला सुरुवात करा';

  @override
  String get regStopWalk => 'थांबवा';

  @override
  String get regClosePolygon => 'हद्द बंद करा';

  @override
  String get regUndoPoint => 'बिंदू मागे घ्या';

  @override
  String get regClearBoundary => 'पुसा';

  @override
  String regPointsCount(int count) {
    return '$count बिंदू';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS अचूकता ±$metres मी';
  }

  @override
  String get regAccuracyWaiting => 'GPS ची वाट पाहत आहे…';

  @override
  String get regLocationOff => 'हद्दीवर चालण्यासाठी लोकेशन सुरू करा';

  @override
  String get regLocationDenied => 'हद्दीवर चालण्यासाठी लोकेशन परवानगी हवी';

  @override
  String get regTapHint => 'नकाशावर शेताचे चारही कोपरे टॅप करा';

  @override
  String get regWalkHint => 'शेताच्या कडेने चाला. चालताना बिंदू जोडले जातील.';

  @override
  String regComputedArea(String acres) {
    return 'मोजलेले क्षेत्र $acres एकर';
  }

  @override
  String get regAreaLabel => 'क्षेत्र एकरात';

  @override
  String get regAreaHint => 'शेतकरी सांगतो तसे';

  @override
  String get regUseMeasured => 'मोजलेले वापरा';

  @override
  String get regAreaWarning =>
      'नोंदवलेले क्षेत्र मोजलेल्या क्षेत्रापेक्षा 30% हून जास्त वेगळे आहे. जतन करण्यापूर्वी तपासा.';

  @override
  String get regBoundaryInvalid =>
      'हद्द स्वतःला छेदते आहे. शेवटचे बिंदू मागे घेऊन पुन्हा प्रयत्न करा.';

  @override
  String get regFarmNameLabel => 'शेताचे नाव (ऐच्छिक)';

  @override
  String get regFarmNameHint => 'घरचे शेत';

  @override
  String get regSoilLabel => 'मातीचा प्रकार';

  @override
  String get regIrrigationLabel => 'सिंचन';

  @override
  String get regFarmPhoto => 'शेताचा फोटो (ऐच्छिक)';

  @override
  String get regTakePhoto => 'फोटो काढा';

  @override
  String get regPhotoAdded => 'फोटो जोडला';

  @override
  String get regPhotoRemove => 'काढा';

  @override
  String regFarmPhotosCount(int count) {
    return '$count फोटो';
  }

  @override
  String get regCropsHelp => 'या हंगामात या शेतात असलेले प्रत्येक पीक जोडा.';

  @override
  String get regAddCrop => 'पीक जोडा';

  @override
  String get regCropLabel => 'पीक';

  @override
  String get regVarietyLabel => 'वाण';

  @override
  String get regVarietyHint => 'उदा. MTU-1010';

  @override
  String get regSowingDateLabel => 'पेरणीची तारीख';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'हंगाम: $season';
  }

  @override
  String get regPlotAreaLabel => 'क्षेत्र (एकर, ऐच्छिक)';

  @override
  String get regRemoveCrop => 'पीक काढा';

  @override
  String regPlotTitle(int index) {
    return 'पीक $index';
  }

  @override
  String get regAddFarm => 'आणखी एक शेत जोडा';

  @override
  String regFarmsCount(int count) {
    return '$count शेते';
  }

  @override
  String regFarmIndex(int index) {
    return 'शेत $index';
  }

  @override
  String get regConsentIntro => 'हे शेतकऱ्याला त्यांच्या भाषेत वाचून दाखवा.';

  @override
  String get regConsentNotice =>
      'पीक सल्ला देण्यासाठी आणि भेटींच्या नोंदी ठेवण्यासाठी आम्ही तुमचे नाव, फोन, गाव आणि शेताचा तपशील ठेवू. तुम्ही केव्हाही आम्हाला थांबवायला सांगू शकता.';

  @override
  String get regConsentMarketingNotice =>
      'तुमच्या परवानगीने आम्ही SMS किंवा WhatsApp वर ऑफर आणि शेतीच्या टिप्सही पाठवू.';

  @override
  String get regConsentGiven => 'शेतकरी सहमत आहे';

  @override
  String get regReviewFarmer => 'शेतकरी';

  @override
  String get regReviewFarms => 'शेते आणि पिके';

  @override
  String get regReviewConsent => 'संमती';

  @override
  String get regReviewSyncNote =>
      'आता या फोनवर जतन झाले; नेटवर्क आल्यावर सर्व्हरला पाठवले जाईल.';

  @override
  String get regSave => 'शेतकरी जतन करा';

  @override
  String get regSaveFarm => 'शेत जतन करा';

  @override
  String get regEdit => 'संपादित करा';

  @override
  String get regSaved => 'शेतकरी जतन झाला';

  @override
  String get regIssueName => 'शेतकऱ्याचे नाव नोंदवा';

  @override
  String get regIssuePhoneUnverified => 'फोन पडताळा किंवा नंतर पडताळा निवडा';

  @override
  String get regIssueVillage => 'गाव निवडा';

  @override
  String get regIssueLanguage => 'शेतकऱ्याची भाषा निवडा';

  @override
  String get regIssueBoundary => 'हद्दीचे किमान 3 बिंदू चिन्हांकित करा';

  @override
  String get regIssueArea => 'क्षेत्र एकरात नोंदवा';

  @override
  String get regIssueCrop => 'किमान एक पीक जोडा';

  @override
  String get regIssueSowingDate => 'प्रत्येक पिकाची पेरणीची तारीख नोंदवा';

  @override
  String get regIssueConsent => 'नोंदणीसाठी डेटा संमती आवश्यक आहे';

  @override
  String get soilBlack => 'काळी माती';

  @override
  String get soilRed => 'तांबडी माती';

  @override
  String get soilSandy => 'वाळूमिश्रित माती';

  @override
  String get soilLoamy => 'पोयटा माती';

  @override
  String get soilClay => 'चिकण माती';

  @override
  String get soilAlluvial => 'गाळाची माती';

  @override
  String get soilLaterite => 'जांभा माती';

  @override
  String get irrigationRainfed => 'पावसावर आधारित';

  @override
  String get irrigationBorewell => 'बोअरवेल';

  @override
  String get irrigationCanal => 'कालवा';

  @override
  String get irrigationTank => 'तलाव';

  @override
  String get irrigationOpenWell => 'उघडी विहीर';

  @override
  String get irrigationDrip => 'ठिबक';

  @override
  String get irrigationSprinkler => 'तुषार';

  @override
  String get ownershipOwn => 'स्वतःची';

  @override
  String get ownershipLeased => 'भाडेपट्ट्याने';

  @override
  String get seasonKharif => 'खरीप';

  @override
  String get seasonRabi => 'रब्बी';

  @override
  String get seasonZaid => 'झायद (उन्हाळी)';

  @override
  String get profileTabOverview => 'आढावा';

  @override
  String get profileTabVisits => 'भेटी';

  @override
  String get profileTabDiagnoses => 'निदान';

  @override
  String get profileTabOrders => 'ऑर्डर';

  @override
  String get profileTabKhata => 'खाते';

  @override
  String get profileStartVisit => 'भेट सुरू करा';

  @override
  String get profileScout => 'पीक पाहणी';

  @override
  String get profileNewOrder => 'नवीन ऑर्डर';

  @override
  String get profileCollect => 'वसुली';

  @override
  String get profileComingSoon => 'पुढील अपडेटमध्ये येईल';

  @override
  String get profileVisitsEmpty => 'अजून भेटी नाहीत';

  @override
  String get profileDiagnosesEmpty => 'अजून निदान नाहीत';

  @override
  String get profileOrdersEmpty => 'अजून ऑर्डर नाहीत';

  @override
  String get profileKhataEmpty => 'अजून खात्यात नोंदी नाहीत';

  @override
  String get profilePhone => 'फोन';

  @override
  String get profileLandmark => 'खूण';

  @override
  String get profileLanguage => 'भाषा';

  @override
  String get profileOwnership => 'जमीन';

  @override
  String get profileFarms => 'शेते';

  @override
  String profileAcres(String acres) {
    return '$acres एकर';
  }

  @override
  String get profileAddFarm => 'शेत जोडा';

  @override
  String get profileEditFarm => 'शेत संपादित करा';

  @override
  String profileFarmPlots(int count) {
    return '$count पिके';
  }

  @override
  String get profileNoFarms => 'अजून शेते नाहीत';

  @override
  String get profileDuplicateTitle => 'दुबार — एकत्र करायचे?';

  @override
  String get profileDuplicateBody =>
      'सर्व्हरवर या नंबरचा शेतकरी आधीच आहे. असलेली नोंद उघडून तपशील एकत्र करा.';

  @override
  String get profileRejectedTitle => 'सिंक नाकारले';

  @override
  String get profileRejectedHelp =>
      'दुरुस्त करून पुन्हा प्रयत्न करण्यासाठी सिंक तपशील उघडा.';

  @override
  String get profileNotFound => 'शेतकरी सापडला नाही';

  @override
  String get profileVerifyPhone => 'फोन पडताळा';

  @override
  String get consentGiven => 'दिली';

  @override
  String get consentNotGiven => 'दिली नाही';

  @override
  String get farmEditTitle => 'शेत संपादित करा';

  @override
  String get farmAddTitle => 'शेत जोडा';

  @override
  String get mapNoBoundary => 'अजून हद्द नाही';

  @override
  String get mapAttribution => '© OpenStreetMap योगदानकर्ते';

  @override
  String get mapCurrentPosition => 'तुमचे स्थान';

  @override
  String mapCorner(int index) {
    return 'कोपरा $index';
  }

  @override
  String get mapFarmBoundary => 'शेताची हद्द';

  @override
  String get dutyNotificationTitle => 'ड्युटीवर — लोकेशन सुरू';

  @override
  String get dutyChannelName => 'ड्युटी';

  @override
  String get dutyAlertsChannelName => 'ड्युटी सूचना';

  @override
  String get dutyPromptTitle => 'अजूनही ड्युटीवर आहात?';

  @override
  String dutyPromptBody(String time) {
    return '$time वाजता संपेल';
  }

  @override
  String get dutyEndedTitle => 'ड्युटी संपली';

  @override
  String dutyAutoEndedBody(String time) {
    return 'तुमचा दिवस $time वाजता आपोआप संपला.';
  }

  @override
  String get dutyServerEndedBody =>
      'सर्व्हरने तुमची ड्युटी संपवली (निष्क्रियता किंवा दिवसाचा शेवट).';

  @override
  String dutyAutoEndAt(String time) {
    return '$time वाजता आपोआप संपेल';
  }

  @override
  String get dutyBlockedPolicy => 'ड्युटीवर जाण्यासाठी लोकेशन धोरण स्वीकारा';

  @override
  String get dutyReviewPolicy => 'धोरण पाहा';

  @override
  String dutyPointsPending(int count) {
    return '$count पॉइंट अपलोडची वाट पाहत आहेत';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'तुम्ही आधीच दुसऱ्या डिव्हाइसवर ड्युटीवर आहात. हे बंदच राहील.';

  @override
  String get dutyNoticePolicy =>
      'ड्युटीवर जाण्यापूर्वी सध्याचे लोकेशन धोरण स्वीकारा.';

  @override
  String get dutyNoticeLocationUnavailable =>
      'तुमचे लोकेशन मिळू शकले नाही. लोकेशन सुरू करून पुन्हा प्रयत्न करा.';

  @override
  String get integrityBanner =>
      'काही डिव्हाइस तपासण्यांत समस्या आढळल्या; भेटींचे पुनरावलोकन होऊ शकते.';

  @override
  String get disclosureIntro =>
      'सुरू करण्यापूर्वी, मित्र काय नोंदवते आणि का हे येथे आहे.';

  @override
  String disclosureVersion(String version) {
    return 'धोरण आवृत्ती $version';
  }

  @override
  String get disclosureUpdated =>
      'लोकेशन धोरण बदलले आहे. कृपया नवीन आवृत्ती वाचून स्वीकारा.';

  @override
  String get policySheetTitle => 'लोकेशन धोरण';

  @override
  String get locationPolicyText =>
      'मित्र लोकेशन धोरण (आवृत्ती 2026-09-v1)\n\n1. आम्ही काय गोळा करतो. तुम्ही ड्युटीवर असताना, मित्र तुमचे लोकेशन (अक्षांश, रेखांश, अचूकता, वेग, दिशा), वेळ, बॅटरी पातळी आणि मूलभूत डिव्हाइस तपासण्या (मॉक लोकेशन, रूट केलेले डिव्हाइस, घड्याळातील फरक) नोंदवते. भेटींदरम्यान तुम्ही घेतलेले फोटो, नोंदी आणि शेतकऱ्यांची पुष्टी देखील नोंदवली जाते.\n\n2. फक्त ड्युटीवर असताना. तुम्ही ड्युटी सुरू केल्यानंतरच लोकेशन नोंदवले जाते; ड्युटी बंद करताच, संस्थेच्या ठरलेल्या वेळी दिवस संपल्यावर (डीफॉल्ट 20:00) किंवा घरी 60 मिनिटे निष्क्रिय राहिल्यावर ते थांबते. ड्युटी बंद असताना काहीही नोंदवले जात नाही, आणि लोकेशन सुरू असेपर्यंत सूचना नेहमी दिसते.\n\n3. आम्ही ते का गोळा करतो. तुमच्या ट्रॅकवरून प्रवास भत्त्यासाठी किलोमीटर मोजले जातात, आणि भेटीच्या वेळी तुमचे लोकेशन त्या भेटीचे श्रेय देते. ट्रॅक नाही तर आपोआप प्रवास भत्ता नाही आणि पडताळलेली भेट नाही.\n\n4. ते कोण पाहू शकते. तुमचे क्लस्टर हेड, संचालक आणि संस्थेचे मालक त्यांच्या क्षेत्रासाठी तुमचा ट्रॅक आणि भेटी पाहू शकतात, आणि ऑडिटर फ्लॅग केलेल्या भेटींचे पुनरावलोकन करू शकतात. स्टोअर मॅनेजर आणि शेतकरी तुमचे लोकेशन कधीही पाहत नाहीत. कच्चे पॉइंट 180 दिवस ठेवले जातात आणि नंतर दैनिक बेरजेत रूपांतरित केले जातात.';

  @override
  String get permissionsTitle => 'मित्रला लागणाऱ्या परवानग्या';

  @override
  String get permissionsIntro =>
      'मित्र या एक-एक करून विचारेल. त्या नंतर सेटिंग्जमध्ये बदलता येतील.';

  @override
  String get permLocationTitle => 'लोकेशन';

  @override
  String get permLocationBody =>
      'ड्युटीवर तुमचा ट्रॅक नोंदवण्यासाठी आणि तुम्ही शेतावर आहात का हे तपासण्यासाठी.';

  @override
  String get permBackgroundTitle => 'लोकेशन नेहमी';

  @override
  String get permBackgroundBody =>
      'स्क्रीन बंद असतानाही ट्रॅकिंग सुरू राहण्यासाठी \"नेहमी परवानगी द्या\" निवडा. तरीही हे फक्त ड्युटीवर असतानाच चालते.';

  @override
  String get permCameraTitle => 'कॅमेरा';

  @override
  String get permCameraBody =>
      'अ‍ॅपमध्ये घेतलेल्या शेत आणि भेटीच्या फोटोंसाठी.';

  @override
  String get permNotificationsTitle => 'सूचना';

  @override
  String get permNotificationsBody =>
      'ड्युटीची सूचना दाखवण्यासाठी आणि ड्युटी संपण्यापूर्वी आठवण करून देण्यासाठी.';

  @override
  String get permGranted => 'परवानगी दिली';

  @override
  String get permDenied => 'परवानगी नाही';

  @override
  String get permOpenSettings => 'सेटिंग्ज उघडा';

  @override
  String get permAllow => 'परवानगी द्या';

  @override
  String get registeredTitle => 'डिव्हाइस नोंदणीकृत';

  @override
  String get registeredBody =>
      'तुम्ही तयार आहात. दिवस सुरू करण्यासाठी होमवरून ड्युटीवर जा.';

  @override
  String get registeredStart => 'होमवर जा';

  @override
  String get homeTitle => 'होम';

  @override
  String get homeTodayStats => 'आज';

  @override
  String get statVisitsVerified => 'पडताळलेल्या भेटी';

  @override
  String get statFarmersAdded => 'जोडलेले शेतकरी';

  @override
  String get statCollections => 'वसुली';

  @override
  String get homeNextUp => 'पुढील';

  @override
  String get homeNextUpEmpty => 'अजून बीट प्लॅन नाही';

  @override
  String get homeNextUpEmptyHelp =>
      'तुमचे क्लस्टर हेड गावे नेमून देतील. तोपर्यंत शेतकरी जोडा आणि भेटी सुरू करा.';

  @override
  String get homeQuickActions => 'जलद कृती';

  @override
  String get actionStartVisit => 'भेट सुरू करा';

  @override
  String get actionScoutCrop => 'पीक पाहणी';

  @override
  String get actionCollectPayment => 'पैसे गोळा करा';

  @override
  String get comingSoon => 'लवकरच येत आहे';

  @override
  String get navHome => 'होम';

  @override
  String get navFarmers => 'शेतकरी';

  @override
  String get navVisits => 'भेटी';

  @override
  String get navOrders => 'ऑर्डर';

  @override
  String get navMe => 'मी';

  @override
  String get myDayTitle => 'माझा दिवस';

  @override
  String myDayKm(String km) {
    return 'आज $km कि.मी.';
  }

  @override
  String get myDayEmpty => 'आज अजून ड्युटी नाही';

  @override
  String get myDayEmptyHelp =>
      'होमवरून ड्युटीवर जा; तुमचा ट्रॅक आणि कि.मी. येथे दिसतील.';

  @override
  String myDaySession(String start, String end) {
    return 'ड्युटी $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return '$start पासून ड्युटीवर';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending प्रलंबित · $accepted स्वीकृत';
  }

  @override
  String get myDayGapsTitle => 'अंतर आणि कारणे';

  @override
  String get myDayGapsHelp => 'अंतराची कारणे पुढील अपडेटसह येतील.';

  @override
  String get myDayEndReasonManual => 'तुम्ही संपवली';

  @override
  String get myDayEndReasonAutoTime => 'दिवसाच्या शेवटी संपली';

  @override
  String get myDayEndReasonAutoIdle => 'निष्क्रियतेनंतर संपली';

  @override
  String get myDayEndReasonForced => 'मॅनेजरने संपवली';

  @override
  String get myDayEndReasonRejected => 'नोंद झाली नाही';

  @override
  String get syncEntityDutySession => 'ड्युटी सत्र';

  @override
  String get syncEntityLocationBatch => 'लोकेशन पॉइंट';

  @override
  String get syncEntityPolicyAcceptance => 'धोरण स्वीकृती';

  @override
  String get visitsTitle => 'भेटी';

  @override
  String get visitsTabToday => 'आज';

  @override
  String get visitsTabWeek => 'या आठवड्यात';

  @override
  String get visitsFilterAll => 'सर्व';

  @override
  String get visitsEmptyTitle => 'अद्याप भेटी नाहीत';

  @override
  String get visitsEmptyHelp =>
      'शेतकरी प्रोफाइलमधून किंवा खालील बटणाने भेट सुरू करा.';

  @override
  String get visitStatusOpen => 'सुरू आहे';

  @override
  String get visitCardPending => 'ऑनलाइन झाल्यावर सिंक होईल';

  @override
  String get visitCardFailed => 'लक्ष द्यावे लागेल';

  @override
  String get visitChooseFarmer => 'शेतकरी निवडा';

  @override
  String get visitFarmLabel => 'शेत';

  @override
  String get visitFarmNoBoundary => 'या शेताची सीमा नोंदलेली नाही';

  @override
  String get visitPurposeLabel => 'उद्देश';

  @override
  String get visitOffDutyTitle => 'आधी ड्युटीवर जा';

  @override
  String get visitOffDutyBody =>
      'भेटी फक्त ड्युटीवर असतानाच नोंदवल्या जातात. होममधून ड्युटी सुरू करा आणि परत या.';

  @override
  String get visitGoHome => 'होमवर जा';

  @override
  String get visitLocating => 'तुमचे ठिकाण घेत आहोत…';

  @override
  String get visitNoFix =>
      'तुमचे ठिकाण मिळाले नाही. मोकळ्या आकाशाखाली जाऊन पुन्हा प्रयत्न करा.';

  @override
  String get visitRefreshLocation => 'ठिकाण पुन्हा तपासा';

  @override
  String visitAccuracy(int metres) {
    return 'अचूकता ±$metres मी';
  }

  @override
  String get visitInsideGeofence => 'तुम्ही शेताच्या जिओफेन्सच्या आत आहात';

  @override
  String get visitAtMeetingPoint => 'तुम्ही गावाच्या बैठक स्थळी आहात';

  @override
  String visitOutsideFarm(int distance, int radius) {
    return 'शेताच्या सीमेपासून $distance मी दूर; जिओफेन्स $radius मी आहे.';
  }

  @override
  String visitOutsideMeeting(int distance, int radius) {
    return 'बैठक स्थळापासून $distance मी दूर; परवानगी असलेली त्रिज्या $radius मी आहे.';
  }

  @override
  String get visitNoTarget =>
      'या शेताची सीमा नाही आणि गावाचे बैठक स्थळ नाही. ओव्हरराइड नोटसह चेक इन करा.';

  @override
  String get visitRequestOverride => 'ओव्हरराइड मागा';

  @override
  String get visitOverrideNoteLabel => 'तुम्ही इथून का चेक इन करत आहात?';

  @override
  String get visitOverrideNoteHint => 'उदा. शेतकऱ्याला बाजारात भेटलो';

  @override
  String get visitOverrideNoteRequired => 'ओव्हरराइड मागण्यासाठी नोट लिहा';

  @override
  String get visitOverrideHelp =>
      'तुमचा क्लस्टर हेड ओव्हरराइडचे पुनरावलोकन करेल. मंजूर झाल्यासच भेटीला जिओफेन्स क्रेडिट मिळेल.';

  @override
  String get visitCheckIn => 'चेक इन';

  @override
  String get visitCheckInOverride => 'ओव्हरराइडसह चेक इन';

  @override
  String get visitInProgress => 'भेट सुरू आहे';

  @override
  String get visitTimerLabel => 'भेटीचा वेळ';

  @override
  String visitMinDuration(int minutes) {
    return 'किमान $minutes मिनिटे';
  }

  @override
  String visitDurationNeeds(int minutes, int minimum) {
    return '$minimum मिनिटांपैकी $minutes मिनिटे';
  }

  @override
  String visitUnderMinimum(int minutes) {
    return 'किमान $minutes मिनिटांपेक्षा कमी. भेट फ्लॅग होईल, नाकारली जाणार नाही.';
  }

  @override
  String get visitPhotos => 'फोटो';

  @override
  String get visitTakePhoto => 'फोटो काढा';

  @override
  String visitPhotoCount(int count) {
    return '$count फोटो';
  }

  @override
  String get visitPhotosHelp => 'फक्त अ‍ॅप कॅमेरा. शेतावर किमान एक फोटो काढा.';

  @override
  String get visitNotesLabel => 'नोंदी';

  @override
  String get visitNotesHint => 'तुम्ही काय पाहिले किंवा कोणता सल्ला दिला?';

  @override
  String get visitCropStageLabel => 'पीक अवस्था';

  @override
  String get cropStageSown => 'पेरणी';

  @override
  String get cropStageMaturity => 'परिपक्वता';

  @override
  String get cropStageHarvested => 'कापणी झाली';

  @override
  String get visitProofTitle => 'भेटीचा पुरावा';

  @override
  String get visitExpectedScore => 'अपेक्षित गुण';

  @override
  String get visitServerScore => 'सर्व्हरकडून गुण';

  @override
  String get visitConfirmFarmer => 'शेतकऱ्याची पुष्टी';

  @override
  String get visitCheckOut => 'चेक आउट';

  @override
  String get visitCheckInPending => 'ऑनलाइन झाल्यावर चेक इन सिंक होईल';

  @override
  String get visitCheckInSynced => 'चेक इन सिंक झाले';

  @override
  String get visitRejectedTitle => 'चेक इन नाकारले';

  @override
  String visitRejectedOutside(int distance) {
    return 'सर्व्हरने तुम्हाला जिओफेन्सच्या $distance मी बाहेर ठरवले.';
  }

  @override
  String get visitRejectedNoTarget =>
      'तुमचे ठिकाण तपासण्यासाठी सर्व्हरला काहीही सापडले नाही.';

  @override
  String get visitRetryFromFarm => 'शेतातून पुन्हा प्रयत्न करा';

  @override
  String visitRetryStillOutside(int distance) {
    return 'अजूनही $distance मी बाहेर आहात. जवळ जा किंवा ओव्हरराइड मागा.';
  }

  @override
  String get visitRetryQueued =>
      'तुमच्या सध्याच्या ठिकाणासह चेक इन पुन्हा रांगेत आहे.';

  @override
  String get proofGeofenceOverride => 'ओव्हरराइड मागितले; क्लस्टर हेडची वाट';

  @override
  String get proofGeofenceOutside => 'जिओफेन्सच्या बाहेर';

  @override
  String get proofPhotoDone => 'ठिकाणासह फोटो घेतला';

  @override
  String get proofDurationDone => 'किमान कालावधी पूर्ण झाला';

  @override
  String get proofIntegrityIssue => 'डिव्हाइस तपासणीत समस्या; या भागाचे गुण 0';

  @override
  String get visitConfirmTitle => 'शेतकऱ्याची पुष्टी';

  @override
  String get visitConfirmIntro =>
      'शेतकऱ्याला यापैकी एका मार्गाने या भेटीची पुष्टी करण्यास सांगा.';

  @override
  String get visitConfirmOtp => 'SMS द्वारे OTP';

  @override
  String get visitConfirmOtpHelp =>
      'शेतकऱ्याच्या फोनवर कोड जाईल; तो इथे टाइप करा.';

  @override
  String get visitConfirmPush => 'किसान अ‍ॅपमध्ये विचारा';

  @override
  String get visitConfirmPushHelp =>
      'शेतकरी त्यांच्या अ‍ॅपमध्ये पुष्टी करा दाबतो.';

  @override
  String get visitConfirmQr => 'QR दाखवा';

  @override
  String get visitConfirmQrHelp => 'शेतकरी हे किसान अ‍ॅपने स्कॅन करतो.';

  @override
  String get visitConfirmNeedsNetwork =>
      'यासाठी नेटवर्क लागते. ऑनलाइन झाल्यावर पुन्हा प्रयत्न करा.';

  @override
  String get visitConfirmQrNeedsSync =>
      'QR साठी आधी एकदा सिंक लागते. एकदा कनेक्ट करा आणि परत या.';

  @override
  String get visitConfirmNotSynced =>
      'चेक इन अजून सर्व्हरवर पोहोचले नाही. सिंक करून पुन्हा प्रयत्न करा.';

  @override
  String get visitConfirmQueued =>
      'विनंती जतन झाली. ऑनलाइन होताच शेतकऱ्याच्या अ‍ॅपवर जाईल.';

  @override
  String get visitConfirmWaiting => 'शेतकऱ्याची वाट पाहत आहोत…';

  @override
  String get visitConfirmWaitingPush =>
      'आम्ही किसान अ‍ॅपमध्ये शेतकऱ्याला विचारले आहे. पुष्टी होताच ही स्क्रीन अपडेट होईल.';

  @override
  String get visitConfirmQrWaiting => 'शेतकरी स्कॅन करेपर्यंत वाट पाहत आहोत…';

  @override
  String get visitConfirmed => 'शेतकऱ्याने पुष्टी केली';

  @override
  String visitConfirmedVia(String channel) {
    return '$channel द्वारे पुष्टी झाली';
  }

  @override
  String visitConfirmOtpSent(String phone) {
    return '$phone वर कोड पाठवला';
  }

  @override
  String get visitConfirmAlready => 'या भेटीची पुष्टी आधीच झाली आहे.';

  @override
  String get visitConfirmRefused =>
      'सध्या शेतकऱ्याला अशा प्रकारे विचारता येत नाही. दुसरा मार्ग वापरा.';

  @override
  String get visitConfirmContinue => 'चेक आउटकडे जा';

  @override
  String get visitConfirmLater => 'नंतर पुष्टी करा';

  @override
  String visitConfirmExpires(int minutes) {
    return '$minutes मिनिटांत संपेल';
  }

  @override
  String get visitConfirmChooseAnother => 'दुसरा मार्ग निवडा';

  @override
  String get visitSummaryTitle => 'चेक आउट सारांश';

  @override
  String get visitSummaryDuration => 'कालावधी';

  @override
  String get visitSummaryMissing => 'काय कमी होते';

  @override
  String get visitSummaryComplete => 'सर्व काही व्यवस्थित आहे';

  @override
  String get visitSummaryPending =>
      'पुढील सिंकनंतर सर्व्हर गुणांची पुष्टी करेल';

  @override
  String get visitSummaryServer => 'सर्व्हरने गुणांची पुष्टी केली';

  @override
  String get visitSummaryNotCheckedOut => 'ही भेट अजून सुरू आहे.';

  @override
  String get visitSummaryOverridePending =>
      'ओव्हरराइड पुनरावलोकनाच्या प्रतीक्षेत';

  @override
  String get visitDone => 'झाले';

  @override
  String get syncEntityVisit => 'भेट';

  @override
  String get syncEntityVisitPhoto => 'भेटीचा फोटो';

  @override
  String get syncEntityVisitConfirmation => 'शेतकऱ्याची पुष्टी';

  @override
  String get catalogTitle => 'उत्पादने';

  @override
  String catalogForFarmer(String name) {
    return '$name साठी';
  }

  @override
  String get catalogSearchHint => 'नाव, ब्रँड किंवा घटक शोधा';

  @override
  String get catalogCategoryAll => 'सर्व';

  @override
  String get catalogCategorySeed => 'बियाणे';

  @override
  String get catalogCategoryFertiliser => 'खते';

  @override
  String get catalogCategoryPesticide => 'कीटकनाशके';

  @override
  String get catalogCategoryFungicide => 'बुरशीनाशके';

  @override
  String get catalogCategoryHerbicide => 'तणनाशके';

  @override
  String get catalogCategoryGrowth => 'वाढ वर्धके';

  @override
  String get catalogCategoryTool => 'अवजारे';

  @override
  String get catalogCategoryOther => 'इतर';

  @override
  String catalogAsOf(String time) {
    return '$time पर्यंतचे दर आणि साठा';
  }

  @override
  String catalogStale(String time) {
    return 'दर आणि साठा जुने असू शकतात ($time पर्यंतचे). इंटरनेट असताना रिफ्रेश करा.';
  }

  @override
  String get catalogNeverLoaded => 'उत्पादन यादी अजून या फोनवर नाही';

  @override
  String get catalogNeverLoadedHelp =>
      'उत्पादने आणि दर डाउनलोड करण्यासाठी इंटरनेटशी जोडा.';

  @override
  String get catalogRefresh => 'रिफ्रेश करा';

  @override
  String get catalogRefreshFailed =>
      'रिफ्रेश झाले नाही. जतन केलेली उत्पादने दाखवत आहोत.';

  @override
  String get catalogEmpty => 'जुळणारे उत्पादन नाही';

  @override
  String get catalogEmptyHelp => 'दुसरे नाव किंवा प्रकार वापरून पाहा.';

  @override
  String get catalogStoreUnknown =>
      'दुकान अजून माहीत नाही. पुढच्या सिंकनंतर साठा दिसेल.';

  @override
  String get productPriceEstimate => 'अंदाजे किंमत';

  @override
  String productStockNearest(int count) {
    return 'जवळच्या दुकानात $count साठ्यात';
  }

  @override
  String productStockAsOf(String time) {
    return '$time पर्यंत';
  }

  @override
  String productInCart(int count) {
    return 'कार्टमध्ये $count';
  }

  @override
  String get cartEstimatedTotal => 'अंदाजे एकूण';

  @override
  String get cartViewCart => 'कार्ट पाहा';

  @override
  String get cartTitle => 'कार्ट';

  @override
  String get cartEmpty => 'कार्ट रिकामी आहे';

  @override
  String get cartEmptyHelp => 'यादीतून उत्पादने जोडा.';

  @override
  String get cartAddMore => 'आणखी उत्पादने जोडा';

  @override
  String get cartSubtotal => 'उप-एकूण (अंदाज)';

  @override
  String get cartTax => 'GST (अंदाज)';

  @override
  String get cartEstimateNote =>
      'दर जतन केलेल्या दरपत्रकातील अंदाज आहेत. ऑर्डर सिंक झाल्यावर दुकान अंतिम रक्कम निश्चित करते.';

  @override
  String get cartFulfilment => 'शेतकऱ्याला माल कसा मिळेल?';

  @override
  String get fulfilmentPickup => 'दुकानातून घेणे';

  @override
  String get fulfilmentDelivery => 'घरपोच';

  @override
  String get cartChoosePayment => 'पेमेंट निवडा';

  @override
  String get cartDecrease => 'एक कमी करा';

  @override
  String get cartIncrease => 'एक वाढवा';

  @override
  String cartShortLine(String available, String requested) {
    return 'दुकानात फक्त $available उपलब्ध ($requested मागितले).';
  }

  @override
  String cartUseAvailable(String available) {
    return '$available ठेवा';
  }

  @override
  String get cartShortTitle =>
      'दुकानात काही माल कमी आहे. प्रमाण बदलून पुन्हा पाठवा.';

  @override
  String get checkoutTitle => 'पेमेंट';

  @override
  String get checkoutOrderAmount => 'ऑर्डर एकूण (अंदाज)';

  @override
  String get checkoutDuesAmount => 'वसूल करायची रक्कम (₹)';

  @override
  String checkoutDuesBalance(String amount) {
    return 'थकबाकी $amount';
  }

  @override
  String checkoutDuesTooMuch(String amount) {
    return '$amount पर्यंत रक्कम टाका';
  }

  @override
  String get checkoutDuesInvalid => 'रक्कम टाका';

  @override
  String get checkoutPlaceOrder => 'ऑर्डर द्या';

  @override
  String get checkoutCollect => 'वसूल करा';

  @override
  String get checkoutNeedsInternet => 'इंटरनेट हवे: रोख किंवा उधारी वापरा';

  @override
  String get checkoutCreditOrdersOnly => 'उधारी फक्त ऑर्डरसाठी';

  @override
  String checkoutCreditLeft(String amount) {
    return 'उरलेली मर्यादा $amount';
  }

  @override
  String get checkoutOfflineNote =>
      'तुम्ही ऑफलाइन आहात. रोख आणि उधारी फोनवर जतन होऊन इंटरनेट आल्यावर पाठवली जाईल.';

  @override
  String get checkoutOrderNotSynced =>
      'ऑर्डर अजून सर्व्हरवर पोहोचली नाही. इंटरनेट असताना पुन्हा प्रयत्न करा किंवा रोख घ्या.';

  @override
  String get checkoutNetworkError =>
      'सर्व्हरशी संपर्क झाला नाही. इंटरनेट तपासून पुन्हा प्रयत्न करा.';

  @override
  String get checkoutAlreadyPaid => 'या ऑर्डरचे पेमेंट आधीच झाले आहे.';

  @override
  String get checkoutAmountMismatch =>
      'सर्व्हरवर रक्कम बदलली आहे. ऑर्डर तपासून पुन्हा प्रयत्न करा.';

  @override
  String get checkoutNothingDue => 'या शेतकऱ्याची काहीही थकबाकी नाही.';

  @override
  String checkoutRefused(String code) {
    return 'पेमेंट तयार झाले नाही ($code).';
  }

  @override
  String get paymentCard => 'कार्ड';

  @override
  String get paymentDone => 'झाले';

  @override
  String get upiTitle => 'UPI QR';

  @override
  String get upiExpired => 'QR ची मुदत संपली';

  @override
  String get upiCollectCash => 'त्याऐवजी रोख घ्या';

  @override
  String get linkTitle => 'पेमेंट लिंक';

  @override
  String get linkSentTitle => 'पेमेंट लिंक पाठवली';

  @override
  String linkSentVia(String channel) {
    return '$channel ने पाठवली. शेतकऱ्याला लिंक उघडून पैसे भरायला सांगा.';
  }

  @override
  String get channelSms => 'SMS';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get linkResend => 'लिंक पुन्हा पाठवा';

  @override
  String get linkResent => 'लिंक पुन्हा पाठवली';

  @override
  String get linkCheckStatus => 'पेमेंट तपासा';

  @override
  String linkValidUntil(String time) {
    return '$time पर्यंत वैध';
  }

  @override
  String get cashTitle => 'रोख पावती';

  @override
  String get cashAmount => 'घेतलेली रोख';

  @override
  String get cashTakePhoto => 'पावतीचा फोटो घ्या';

  @override
  String get cashRetake => 'पुन्हा घ्या';

  @override
  String get cashSave => 'रोख पेमेंट जतन करा';

  @override
  String get cashPhotoHelp =>
      'शेतकऱ्याला दिलेल्या पावतीचा फोटो घ्या. फक्त ॲपचा कॅमेरा वापरता येतो.';

  @override
  String get cashPhotoBad =>
      'फोटो धूसर किंवा अंधारा आहे. चांगल्या प्रकाशात पुन्हा घ्या.';

  @override
  String get cashSaved => 'रोख जतन झाली. दुकानाची जुळवणी बाकी.';

  @override
  String get cashPendingReconciliation =>
      'दुकानाची जुळवणी बाकी: दिवस संपताना दुकान रोख तपासेल.';

  @override
  String get creditTitle => 'उधारी विक्री';

  @override
  String get creditQueued =>
      'फोनवर जतन झाले. इंटरनेट आल्यावर उधारी मर्यादा तपासली जाईल.';

  @override
  String get creditApprovedTitle => 'शेतकऱ्याच्या खात्यात जोडले';

  @override
  String get creditNeedsApprovalTitle => 'मंजुरी हवी';

  @override
  String get creditNeedsApprovalBody =>
      'ही विक्री शेतकऱ्याच्या उधारी मर्यादेपेक्षा जास्त आहे. मंजुरीसाठी क्लस्टर हेडकडे पाठवली.';

  @override
  String get creditLimit => 'उधारी मर्यादा';

  @override
  String get creditBalance => 'सध्याची थकबाकी';

  @override
  String get creditShortfall => 'मर्यादेपेक्षा जास्त';

  @override
  String get creditSentToClusterHead => 'क्लस्टर हेडकडे पाठवले';

  @override
  String get creditCheckAgain => 'मंजुरी तपासा';

  @override
  String get creditStillPending =>
      'अजून मंजुरी मिळाली नाही. नंतर पुन्हा तपासा.';

  @override
  String get creditOfflineCheck => 'मंजुरी तपासण्यासाठी इंटरनेटशी जोडा.';

  @override
  String get creditUseCash => 'त्याऐवजी रोख घ्या';

  @override
  String get orderTitle => 'ऑर्डर';

  @override
  String get orderPlacedTitle => 'ऑर्डर दिली';

  @override
  String get orderQueuedTitle => 'ऑर्डर जतन झाली, सिंकची वाट';

  @override
  String get orderQueuedHelp => 'फोनवर इंटरनेट येताच ही दुकानाकडे जाईल.';

  @override
  String get orderRejectedTitle => 'दुकान ही ऑर्डर घेऊ शकले नाही';

  @override
  String get orderInsufficientStock => 'दुकानात काही माल कमी आहे:';

  @override
  String orderShortLine(String product, String available, String requested) {
    return '$product: $available उपलब्ध, $requested मागितले';
  }

  @override
  String get orderSkuNotRecommendable =>
      'एका उत्पादनाला या पिकासाठी व किडीसाठी मान्यता नाही (लेबल दावा). ते काढून पुन्हा पाठवा.';

  @override
  String get orderEditAndResend => 'बदलून पुन्हा पाठवा';

  @override
  String get orderSummary => 'सारांश';

  @override
  String get orderSubtotal => 'उप-एकूण';

  @override
  String get orderTax => 'GST';

  @override
  String get orderTotal => 'एकूण';

  @override
  String get orderTotalEstimate => 'एकूण (अंदाज)';

  @override
  String get orderStatusTitle => 'स्थिती';

  @override
  String get orderStatusPlaced => 'ऑर्डर दिली';

  @override
  String get orderStatusReserved => 'साठा राखीव';

  @override
  String get orderStatusPacked => 'पॅक झाले';

  @override
  String get orderStatusReady => 'तयार';

  @override
  String get orderStatusHandedOver => 'सुपूर्द केले';

  @override
  String get orderStatusDelivered => 'पोहोचवले';

  @override
  String get orderStatusCancelled => 'रद्द';

  @override
  String get orderPayments => 'पेमेंट';

  @override
  String get orderNoPayments => 'अजून पेमेंट नाही';

  @override
  String get orderShareInvoice => 'WhatsApp वर बिल पाठवा';

  @override
  String get orderShareOffline => 'बिल पाठवण्यासाठी इंटरनेटशी जोडा.';

  @override
  String get orderShareNoInvoice => 'दुकान ऑर्डर सुपूर्द करताना बिल देते.';

  @override
  String get orderShareFailed => 'बिलाची लिंक मिळाली नाही. पुन्हा प्रयत्न करा.';

  @override
  String orderShareText(String number, String url) {
    return 'बिल $number: $url';
  }

  @override
  String orderInvoiceNo(String number) {
    return 'बिल $number';
  }

  @override
  String get orderCollectPayment => 'पेमेंट घ्या';

  @override
  String get orderPendingSync => 'सिंकची वाट';

  @override
  String get orderRejected => 'लक्ष द्या';

  @override
  String get ordersTitle => 'ऑर्डर';

  @override
  String get ordersEmpty => 'अजून ऑर्डर नाहीत';

  @override
  String get ordersEmptyHelp => 'शेतकऱ्यांसाठी दिलेल्या ऑर्डर येथे दिसतील.';

  @override
  String get ordersNew => 'नवी ऑर्डर';

  @override
  String get ordersCollections => 'वसुली';

  @override
  String get ordersPickFarmer => 'शेतकरी निवडा';

  @override
  String get khataTitle => 'खाते';

  @override
  String khataAsOf(String time) {
    return '$time पर्यंत';
  }

  @override
  String khataOfflineAsOf(String time) {
    return 'ऑफलाइन: $time ला जतन केलेले खाते दाखवत आहोत';
  }

  @override
  String get khataNotLoaded => 'खाते अजून या फोनवर नाही';

  @override
  String get khataNotLoadedHelp => 'शेतकऱ्याचे खाते आणण्यासाठी इंटरनेटशी जोडा.';

  @override
  String khataOverdue(String amount) {
    return 'मुदत संपलेली थकबाकी $amount';
  }

  @override
  String get khataBucket0to30 => '0–30 दिवस';

  @override
  String get khataBucket31to60 => '31–60 दिवस';

  @override
  String get khataBucket61to90 => '61–90 दिवस';

  @override
  String get khataBucket90plus => '90+ दिवस';

  @override
  String khataDueHarvest(String date, String month) {
    return 'देय $date · काढणी $month';
  }

  @override
  String get khataEntryOrder => 'उधारी विक्री';

  @override
  String get khataEntryPayment => 'पेमेंट मिळाले';

  @override
  String get khataEntryAdjustment => 'समायोजन';

  @override
  String get khataPaymentHistory => 'पेमेंट इतिहास';

  @override
  String get khataNoPayments => 'अजून पेमेंट नाहीत';

  @override
  String get khataPendingCollections => 'वसूल झाले, अजून खात्यात नाही';

  @override
  String get collectionsTitle => 'वसुली';

  @override
  String get collectionsToday => 'आज';

  @override
  String get collectionsWeek => 'या आठवड्यात';

  @override
  String get collectionsTotal => 'एकूण वसुली';

  @override
  String get collectionsEmpty => 'अजून वसुली नाही';

  @override
  String get collectionsEmptyHelp => 'तुम्ही वसूल केलेले पेमेंट येथे दिसतील.';

  @override
  String get collectionStateWaitingToSync => 'सिंकची वाट';

  @override
  String get collectionStatePendingReconciliation => 'जुळवणी बाकी';

  @override
  String get collectionStateWaiting => 'पेमेंटची वाट';

  @override
  String get collectionStatePaid => 'भरले';

  @override
  String get collectionStateOnKhata => 'खात्यात';

  @override
  String get collectionStateApprovalNeeded => 'मंजुरी हवी';

  @override
  String get collectionStateFailed => 'अयशस्वी';

  @override
  String get syncEntityOrder => 'ऑर्डर';

  @override
  String get syncEntityPayment => 'पेमेंट';

  @override
  String get storeModeTitle => 'स्टोअर मोड';

  @override
  String get storeSettingsEntryHint => 'विक्री, ऑर्डर, स्टॉक आणि दिवस बंद';

  @override
  String get storeNavHome => 'होम';

  @override
  String get storeNavPos => 'विक्री';

  @override
  String get storeNavQueue => 'ऑर्डर';

  @override
  String get storeNavStock => 'स्टॉक';

  @override
  String get storeNavCredit => 'उधारी';

  @override
  String get storeNavDayClose => 'दिवस बंद';

  @override
  String get storeReadOnlyBanner =>
      'तुम्ही हे स्टोअर पाहत आहात. बदल फक्त स्टोअर टीम करू शकते.';

  @override
  String get storeNotAllowedTitle => 'स्टोअर मोड उपलब्ध नाही';

  @override
  String get storeNotAllowedHelp =>
      'स्टोअर मोड स्टोअर मॅनेजर, अकाउंटंट आणि क्लस्टर हेडसाठी आहे.';

  @override
  String get storeOfflineTitle => 'तुम्ही ऑफलाइन आहात';

  @override
  String get storeOfflineHelp =>
      'स्टोअर मोडला नेटवर्क लागते. कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get storeErrorTitle => 'लोड होऊ शकले नाही';

  @override
  String get storeErrorHelp => 'काहीतरी चुकले. पुन्हा प्रयत्न करा.';

  @override
  String get storeSwitchStore => 'स्टोअर बदला';

  @override
  String get storeHomeTitle => 'स्टोअर होम';

  @override
  String get storeTodaySales => 'आजची विक्री';

  @override
  String storeSalesCount(int count) {
    return 'पेमेंट: $count';
  }

  @override
  String get storeModeUpi => 'UPI QR';

  @override
  String get storeModeCard => 'कार्ड';

  @override
  String get storeModeCash => 'रोख';

  @override
  String get storeModeCredit => 'उधारी (खाते)';

  @override
  String get storeQueueCounts => 'ऑर्डर रांग';

  @override
  String get storeTabNew => 'नवीन';

  @override
  String get storeTabPacking => 'पॅकिंग';

  @override
  String get storeTabReady => 'तयार';

  @override
  String get storeTabHandedOver => 'सुपूर्द केले';

  @override
  String storeTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get storeLowStock => 'कमी स्टॉक';

  @override
  String storeLowStockCount(int count) {
    return 'कमी असलेल्या वस्तू: $count';
  }

  @override
  String storeExpiringCount(int count) {
    return 'लवकरच मुदत संपणारे: $count';
  }

  @override
  String get storeDayCloseStatus => 'दिवस बंद';

  @override
  String get storeDayOpen => 'उघडे, अजून बंद नाही';

  @override
  String storeDayClosed(String time) {
    return '$time वाजता बंद केले';
  }

  @override
  String get storeDayReopened => 'पुन्हा उघडले';

  @override
  String get storeActionNewSale => 'नवी विक्री';

  @override
  String get storeActionReceive => 'माल स्वीकार';

  @override
  String get storeActionTransfer => 'स्टॉक हस्तांतरण';

  @override
  String get storeActionCloseDay => 'दिवस बंद करा';

  @override
  String get storePosTitle => 'विक्री काउंटर';

  @override
  String get storeSearchProducts => 'उत्पादने शोधा';

  @override
  String get storeScan => 'स्कॅन';

  @override
  String get storeEnterCode => 'कोड टाका';

  @override
  String get storeCodeHint => 'बारकोड क्रमांक';

  @override
  String get storeCodeAdd => 'जोडा';

  @override
  String storeScanAdded(String name) {
    return '$name जोडले';
  }

  @override
  String storeScanNotFound(String code) {
    return '$code कोडचे उत्पादन नाही';
  }

  @override
  String get storeScanOffline => 'ऑफलाइन: कोड शोधता येत नाही';

  @override
  String get storeCategoryAll => 'सर्व';

  @override
  String get storeCategorySeed => 'बियाणे';

  @override
  String get storeCategoryFertiliser => 'खते';

  @override
  String get storeCategoryPesticide => 'कीटकनाशके';

  @override
  String get storeCategoryFungicide => 'बुरशीनाशके';

  @override
  String get storeCategoryHerbicide => 'तणनाशके';

  @override
  String get storeCategoryGrowth => 'वाढ वर्धके';

  @override
  String get storeCategoryTool => 'अवजारे';

  @override
  String get storeCategoryOther => 'इतर';

  @override
  String get storeCartTitle => 'कार्ट';

  @override
  String get storeCartEmpty => 'कार्ट रिकामे आहे';

  @override
  String get storeCartEmptyHelp =>
      'जोडण्यासाठी बारकोड स्कॅन करा किंवा उत्पादनावर टॅप करा.';

  @override
  String get storeQtyDecrease => 'कमी करा';

  @override
  String get storeQtyIncrease => 'वाढवा';

  @override
  String get storeSubtotal => 'उप-एकूण (GST पूर्वी)';

  @override
  String get storeGst => 'GST';

  @override
  String get storeTotal => 'एकूण';

  @override
  String get storeRoundOff => 'राउंड ऑफ';

  @override
  String get storeBuyerPhone => 'शेतकऱ्याचा फोन';

  @override
  String get storeBuyerFind => 'शोधा';

  @override
  String get storeBuyerWalkIn => 'थेट आलेल्या ग्राहकासाठी रिकामे ठेवा';

  @override
  String get storeBuyerUnknown => 'नवीन नंबर: विक्री या फोनवर नोंदवली जाईल';

  @override
  String get storeBuyerClear => 'काढा';

  @override
  String get storeNoProducts => 'जुळणारी उत्पादने नाहीत';

  @override
  String get storeCheckoutTitle => 'पेमेंट';

  @override
  String get storePayWith => 'पेमेंट पद्धत';

  @override
  String get storeModeUpiHint => 'शेतकरी QR स्कॅन करतील';

  @override
  String get storeModeCardHint => 'स्टोअर टर्मिनलवर कार्ड';

  @override
  String get storeModeCashHint => 'रोख मोजा, सुट्टे द्या';

  @override
  String get storeModeCreditHint => 'शेतकऱ्याच्या खात्यात जोडा';

  @override
  String get storeCardReference => 'टर्मिनल संदर्भ';

  @override
  String get storeCardReferenceHint => 'स्लिपवरील मंजुरी कोड';

  @override
  String get storeCardReferenceRequired => 'टर्मिनल संदर्भ टाका';

  @override
  String get storeCashTendered => 'मिळालेली रोख';

  @override
  String get storeCashChange => 'परत द्यायचे सुट्टे';

  @override
  String get storeCashShort => 'मिळालेली रोख एकूण रकमेपेक्षा कमी आहे';

  @override
  String get storeCreditNeedsFarmer =>
      'उधारीसाठी नोंदणीकृत शेतकरी हवा. फोनने शेतकरी शोधा.';

  @override
  String get storeInvoicePreview => 'GST बीजक पूर्वावलोकन';

  @override
  String get storeInvoicePreviewNote =>
      'पुष्टी केल्यावर बीजक क्रमांक आणि अंतिम कर सर्व्हरकडून येतो.';

  @override
  String get storeColItem => 'वस्तू';

  @override
  String get storeColHsn => 'HSN';

  @override
  String get storeColQty => 'नग';

  @override
  String get storeColRate => 'दर';

  @override
  String get storeColGst => 'GST';

  @override
  String get storeColAmount => 'रक्कम';

  @override
  String get storeTaxable => 'करपात्र मूल्य';

  @override
  String get storeCgst => 'CGST';

  @override
  String get storeSgst => 'SGST';

  @override
  String get storeIgst => 'IGST';

  @override
  String get storeConfirmSale => 'विक्रीची पुष्टी करा';

  @override
  String get storeOfflineSaleTitle => 'ऑफलाइन: विक्री पूर्ण होऊ शकत नाही';

  @override
  String get storeOfflineSaleHelp =>
      'कार्ट जपून ठेवले आहे. नेटवर्कशी जोडा आणि पुन्हा पुष्टी करा.';

  @override
  String get storeApprovalNeededTitle => 'उधारीची मंजुरी हवी';

  @override
  String storeApprovalNeededHelp(String amount) {
    return 'ही विक्री शेतकऱ्याच्या मर्यादेपेक्षा $amount जास्त आहे. क्लस्टर हेडने मंजुरी द्यावी. कार्ट जपून ठेवले आहे.';
  }

  @override
  String get storeCreditBalance => 'खाते बाकी';

  @override
  String get storeCreditLimit => 'उधारी मर्यादा';

  @override
  String get storeChooseAnotherMode => 'दुसरी पद्धत निवडा';

  @override
  String get storeSaleFailedTitle => 'विक्री पूर्ण झाली नाही';

  @override
  String storeSaleFailed(String code) {
    return 'सर्व्हरने विक्री नाकारली ($code). कार्ट जपून ठेवले आहे.';
  }

  @override
  String get storeInvoiceTitle => 'कर बीजक';

  @override
  String storeInvoiceNo(String number) {
    return 'बीजक $number';
  }

  @override
  String get storeInvoicePaid => 'विक्री पूर्ण झाली';

  @override
  String get storeInvoiceBuyer => 'बिल कोणाच्या नावे';

  @override
  String storeGstin(String gstin) {
    return 'GSTIN $gstin';
  }

  @override
  String get storeAmountInWords => 'रक्कम अक्षरी';

  @override
  String get storeOpenPdf => 'PDF उघडा';

  @override
  String get storeShareWhatsApp => 'WhatsApp वर पाठवा';

  @override
  String get storeShareOther => 'शेअर करा';

  @override
  String storeShareSent(String to) {
    return '$to ला पाठवले';
  }

  @override
  String get storeShareFailed => 'पाठवता आले नाही. पुन्हा प्रयत्न करा.';

  @override
  String get storePdfFailed => 'PDF उघडता आले नाही.';

  @override
  String storeShareText(String number, String amount, String url) {
    return 'बीजक $number, रक्कम $amount: $url';
  }

  @override
  String get storeNextSale => 'पुढील विक्री';

  @override
  String get storeQueueTitle => 'ऑर्डर रांग';

  @override
  String storeOrderRef(String ref) {
    return 'ऑर्डर #$ref';
  }

  @override
  String get storeChannelOfficer => 'फील्ड ऑफिसर';

  @override
  String get storeChannelFarmerApp => 'शेतकरी ॲप';

  @override
  String get storeChannelPos => 'काउंटर';

  @override
  String get storeFulfilmentPickup => 'स्टोअरमधून नेणे';

  @override
  String get storeFulfilmentDelivery => 'डिलिव्हरी';

  @override
  String get storeStatusPlaced => 'ऑर्डर झाले';

  @override
  String get storeStatusReserved => 'स्टॉक राखीव';

  @override
  String get storeStatusPacked => 'पॅक झाले';

  @override
  String get storeStatusReady => 'तयार';

  @override
  String get storeStatusHandedOver => 'सुपूर्द केले';

  @override
  String get storeStatusDelivered => 'पोहोचवले';

  @override
  String get storeStatusCancelled => 'रद्द';

  @override
  String get storeActionReserve => 'स्टॉक राखीव ठेवा';

  @override
  String get storeActionPack => 'पॅक झाले म्हणून नोंदवा';

  @override
  String get storeActionReady => 'तयार म्हणून नोंदवा';

  @override
  String get storeActionHandOver => 'सुपूर्द करा';

  @override
  String get storeActionDeliver => 'पोहोचवले म्हणून नोंदवा';

  @override
  String get storeActionCancel => 'ऑर्डर रद्द करा';

  @override
  String get storeCancelReason => 'रद्द करण्याचे कारण';

  @override
  String get storeKeepOrder => 'ऑर्डर ठेवा';

  @override
  String get storeTransitionFailed =>
      'हा बदल आता करता येत नाही. यादी ताजी केली.';

  @override
  String get storeQueueEmpty => 'येथे ऑर्डर नाहीत';

  @override
  String get storeQueueEmptyHelp =>
      'फील्ड ऑफिसर आणि शेतकरी ॲपचे ऑर्डर येथे दिसतात.';

  @override
  String get storeSelectOrder => 'तपशील पाहण्यासाठी ऑर्डर निवडा';

  @override
  String storeFarmerUnknown(String ref) {
    return 'शेतकरी $ref';
  }

  @override
  String storeOrderMoved(String status) {
    return 'ऑर्डर आता: $status';
  }

  @override
  String get storeStockTitle => 'स्टॉक';

  @override
  String get storeOnHand => 'हाती';

  @override
  String get storeReserved => 'राखीव';

  @override
  String get storeAvailable => 'उपलब्ध';

  @override
  String storeBatch(String number) {
    return 'बॅच $number';
  }

  @override
  String storeExpires(String date) {
    return 'मुदत $date';
  }

  @override
  String get storeNoExpiry => 'मुदत नाही';

  @override
  String get storeExpired => 'मुदत संपली';

  @override
  String get storeExpiring30 => '30 दिवसांत मुदत संपते';

  @override
  String get storeExpiring60 => '60 दिवसांत मुदत संपते';

  @override
  String get storeFilterLow => 'कमी स्टॉक';

  @override
  String get storeFilterExpiring => 'मुदत जवळ';

  @override
  String get storeStockEmpty => 'जुळणारा स्टॉक नाही';

  @override
  String get storeStockEmptyHelp => 'फिल्टर बदला किंवा माल स्वीकारा.';

  @override
  String get storeSelectSku => 'बॅच पाहण्यासाठी वस्तू निवडा';

  @override
  String get storeWriteOff => 'निर्लेखित करा';

  @override
  String get storeWriteOffTitle => 'स्टॉक निर्लेखित करा';

  @override
  String get storeAdjust => 'मोजणी दुरुस्त करा';

  @override
  String get storeAdjustTitle => 'मोजलेल्या स्टॉकनुसार दुरुस्त करा';

  @override
  String get storeCountedQty => 'मोजलेले प्रमाण';

  @override
  String get storeAdjustReasonHint => 'मोजणी वेगळी का आहे';

  @override
  String get storeReason => 'कारण';

  @override
  String get storeReasonRequired => 'कारण टाका';

  @override
  String get storeReasonDamage => 'खराब झाले';

  @override
  String get storeReasonExpiry => 'मुदत संपली';

  @override
  String get storeReasonOther => 'इतर';

  @override
  String get storeQuantity => 'प्रमाण';

  @override
  String get storeQtyRequired => 'शून्यापेक्षा जास्त प्रमाण टाका';

  @override
  String storeQtyTooHigh(String qty) {
    return 'उपलब्धपेक्षा जास्त ($qty)';
  }

  @override
  String storeAvailableQty(String qty) {
    return 'उपलब्ध: $qty';
  }

  @override
  String get storeAddPhoto => 'फोटो जोडा';

  @override
  String get storePhotoAdded => 'फोटो जोडला';

  @override
  String get storeNote => 'टीप';

  @override
  String get storeSubmit => 'जतन करा';

  @override
  String get storeSaved => 'जतन झाले';

  @override
  String get storeNegativeStock => 'राखीव नसलेला स्टॉक पुरेसा नाही';

  @override
  String get storeReceiptTitle => 'माल स्वीकार';

  @override
  String get storeReference => 'पुरवठादार बीजक / संदर्भ';

  @override
  String get storeSku => 'वस्तू';

  @override
  String get storeFindSku => 'वस्तू (निवडा किंवा स्कॅन करा)';

  @override
  String get storeSkuRequired => 'वस्तू निवडा';

  @override
  String get storeBatchNo => 'बॅच क्रमांक';

  @override
  String get storeBatchNoRequired => 'बॅच क्रमांक टाका';

  @override
  String get storeExpiryDate => 'मुदत तारीख';

  @override
  String get storeExpiryPast => 'मुदत तारीख उलटून गेली';

  @override
  String get storeUnitCost => 'एकक किंमत (₹)';

  @override
  String get storeCostRequired => 'किंमत टाका';

  @override
  String get storeAddLine => 'ओळ जोडा';

  @override
  String get storeRemoveLine => 'ओळ काढा';

  @override
  String get storeReceiptSubmit => 'स्टॉक स्वीकारा';

  @override
  String get storeReceiptDone => 'स्टॉक स्वीकारला';

  @override
  String storeReceiptDoneHelp(int lines, String qty) {
    return 'ओळी: $lines · जोडलेली एकके: $qty';
  }

  @override
  String get storeBatchMismatch => 'ही बॅच वेगळ्या मुदत तारखेसह आधीच आहे';

  @override
  String get storeTransferTitle => 'स्टॉक हस्तांतरण';

  @override
  String get storeToStore => 'कोणत्या स्टोअरला';

  @override
  String get storeToStoreRequired => 'पोहोचण्याचे स्टोअर निवडा';

  @override
  String get storeNoOtherStores =>
      'तुमच्यासाठी दुसरे स्टोअर उपलब्ध नाही. तुमच्या क्लस्टर हेडला विचारा.';

  @override
  String get storeChooseBatch => 'बॅच';

  @override
  String get storeFefoSuggested => 'आधी मुदत संपणारे आधी (सूचना)';

  @override
  String get storeTransferSubmit => 'हस्तांतरित करा';

  @override
  String get storeTransferDone => 'हस्तांतरण पूर्ण झाले';

  @override
  String get storeCreditTitle => 'उधारी';

  @override
  String get storeApprovalsEmpty => 'प्रलंबित मंजुरी नाहीत';

  @override
  String get storeApprovalAmount => 'विक्री रक्कम';

  @override
  String get storeShortfall => 'मर्यादेपेक्षा जास्त';

  @override
  String get storeApprove => 'मंजूर करा';

  @override
  String get storeReject => 'नाकारा';

  @override
  String get storeDecisionNote => 'टीप (ऐच्छिक)';

  @override
  String get storeApproved => 'मंजूर. स्टोअर एकदा विक्री पूर्ण करू शकते.';

  @override
  String get storeRejected => 'नाकारले';

  @override
  String get storeApprovalGone => 'या विनंतीवर आधीच निर्णय झाला आहे';

  @override
  String get storeSetLimitTitle => 'शेतकऱ्याची उधारी मर्यादा ठरवा';

  @override
  String get storeLimitAmount => 'मर्यादा (₹)';

  @override
  String get storeLimitAmountRequired => 'मर्यादा रुपयांत टाका';

  @override
  String get storeSetLimit => 'मर्यादा जतन करा';

  @override
  String storeLimitSaved(String amount) {
    return 'मर्यादा जतन झाली: $amount';
  }

  @override
  String storeLimitNeedsClusterHead(String cap) {
    return '$cap पेक्षा जास्त मर्यादेसाठी क्लस्टर हेड हवे. ही मर्यादा ठरवण्यासाठी तुमच्या क्लस्टर हेडला सांगा.';
  }

  @override
  String get storeLimitFarmerNotFound => 'या फोनचा शेतकरी या टॅबलेटवर नाही';

  @override
  String storeManagerCapHint(String cap) {
    return 'तुम्ही $cap पर्यंत ठरवू शकता';
  }

  @override
  String get storeDayCloseTitle => 'दिवस बंद';

  @override
  String get storeCashCount => 'रोख मोजणी';

  @override
  String get storeCoins => 'नाणी (₹)';

  @override
  String get storeExpectedCash => 'अपेक्षित रोख';

  @override
  String get storeCountedCash => 'मोजलेली रोख';

  @override
  String get storeVariance => 'फरक';

  @override
  String storeVarianceOver(String threshold) {
    return 'फरक $threshold पेक्षा जास्त: ऑडिटरना कळवले जाईल';
  }

  @override
  String get storeDepositSlip => 'बँक जमा पावतीचा फोटो';

  @override
  String get storeTakePhoto => 'फोटो काढा';

  @override
  String get storeRetakePhoto => 'पुन्हा फोटो काढा';

  @override
  String get storeSlipRequired => 'जमा पावतीचा फोटो काढा';

  @override
  String get storeCloseNotes => 'नोंदी';

  @override
  String get storeCloseDay => 'दिवस बंद करा';

  @override
  String get storeDayClosedTitle => 'दिवस बंद झाला';

  @override
  String get storeDayAlreadyClosed =>
      'आजचा दिवस आधीच बंद आहे. क्लस्टर हेड तो पुन्हा उघडू शकतात.';

  @override
  String get storeFlagged => 'ऑडिटसाठी चिन्हांकित';

  @override
  String get storePreviewEstimate => 'अंदाज';

  @override
  String get storePreviewLoading => 'पूर्वावलोकन अद्ययावत होत आहे…';

  @override
  String get storePreviewServerNote =>
      'बीजकाप्रमाणेच सर्व्हरने किंमत ठरवली आहे. पुष्टी केल्यावर बीजक क्रमांक मिळतो.';

  @override
  String get storePreviewOffline =>
      'ऑफलाइन पूर्वावलोकन उपलब्ध नाही. रक्कम अंदाजे आहे; पुष्टी केल्यावर सर्व्हर बीजकाची किंमत ठरवतो.';

  @override
  String get storePreviewUnavailable =>
      'पूर्वावलोकन उपलब्ध नाही. रक्कम अंदाजे आहे; पुष्टी केल्यावर सर्व्हर बीजकाची किंमत ठरवतो.';

  @override
  String get storeCheckApproval => 'मंजुरी तपासा';

  @override
  String get storeApprovalPending =>
      'अजून मंजुरी मिळाली नाही. कार्ट जपून ठेवले आहे; नंतर पुन्हा तपासा.';

  @override
  String get storeApprovalRejected =>
      'क्लस्टर हेडने ही उधारी विक्री नाकारली. दुसरी पद्धत निवडा.';

  @override
  String get storeApprovalCheckOffline =>
      'मंजुरी तपासता आली नाही. इंटरनेटशी जोडा आणि पुन्हा प्रयत्न करा.';

  @override
  String get storeTransferSourceNotAllowed =>
      'तुम्ही फक्त तुमच्या स्वतःच्या स्टोअरमधून स्टॉक पाठवू शकता.';

  @override
  String get storeTransferDestinationNotAllowed =>
      'तुम्ही त्या स्टोअरला स्टॉक पाठवू शकत नाही. यादीतून स्टोअर निवडा.';

  @override
  String storeDistanceKm(String km) {
    return '$km किमी दूर';
  }

  @override
  String get creditApprovedSending =>
      'क्लस्टर हेडने मंजुरी दिली. विक्री पाठवत आहे…';

  @override
  String get creditRejectedByClusterHead =>
      'क्लस्टर हेडने ही उधारी विक्री नाकारली. त्याऐवजी रोख घ्या.';

  @override
  String get loginDeviceNotBound =>
      'हा फोन तुमच्या नावावर नोंदणीकृत नाही. तो मंजूर करण्यासाठी तुमच्या ॲडमिनिस्ट्रेटरला सांगा, नंतर पुन्हा साइन इन करा.';

  @override
  String get wipeTitle => 'तुमच्या ॲडमिनिस्ट्रेटरने साइन आउट केले';

  @override
  String get wipeBody =>
      'तुमच्या ॲडमिनिस्ट्रेटरने हा फोन ॲपमधून साइन आउट केला आहे. सुरक्षेसाठी या फोनवरील ॲपचा डेटा हटवला आहे.';

  @override
  String get wipeDeletedList =>
      'हटवले: जतन केलेले शेतकरी, भेटी, ऑर्डर, फोटो आणि अद्याप न पाठवलेले काम. तुमची भाषा सेटिंग तशीच राहते.';

  @override
  String get wipeWhatNext =>
      'ही चूक असल्यास तुमच्या ॲडमिनिस्ट्रेटरशी संपर्क साधा. त्यांनी परवानगी दिल्यावर तुम्ही पुन्हा साइन इन करू शकता.';

  @override
  String get wipeSignInAgain => 'पुन्हा साइन इन करा';

  @override
  String get audioListen => 'ऐका';

  @override
  String get audioUnavailable => 'आवाज उपलब्ध नाही';

  @override
  String get kisanLanguagePrompt => 'तुम्ही मराठी निवडली. पुढे चला दाबा.';

  @override
  String get kisanAbout => 'ॲपबद्दल';

  @override
  String kisanAboutVersion(String app, String version) {
    return '$app आवृत्ती $version';
  }

  @override
  String kisanAcres(String count) {
    return '$count एकर';
  }

  @override
  String kisanAcresPlus(String count) {
    return '$count+ एकर';
  }

  @override
  String get kisanAddToCart => 'टोपलीत टाका';

  @override
  String kisanAsOf(String time) {
    return '$time ला अपडेट';
  }

  @override
  String kisanOfflineAsOf(String time) {
    return 'इंटरनेट नाही. $time ला जतन केलेले';
  }

  @override
  String kisanBalanceNow(String amount) {
    return 'आताची बाकी: $amount';
  }

  @override
  String get kisanBuyProducts => 'माल खरेदी करा';

  @override
  String get kisanCall => 'फोन करा';

  @override
  String get kisanCartEmpty => 'तुमची टोपली रिकामी आहे';

  @override
  String get kisanCartTitle => 'माझी टोपली';

  @override
  String get kisanCheckMyCrop => 'माझे पीक तपासा';

  @override
  String get kisanConfirmWithoutRating => 'रेटिंगशिवाय पक्के करा';

  @override
  String get kisanConsentAgree => 'मी सहमत आहे';

  @override
  String get kisanConsentDataHowToStop =>
      'किसान वापरण्यासाठी हे आवश्यक आहे. थांबवण्यासाठी तुमचे खाते हटवा.';

  @override
  String get kisanConsentDataNeeded =>
      'किसान वापरण्यासाठी पहिल्या कार्डला होय म्हणा.';

  @override
  String get kisanConsentDataNotice =>
      'सल्ला देण्यासाठी आम्ही तुमचे नाव, फोन, गाव, शेत आणि पिकाचे फोटो ठेवतो. तुमचे फील्ड अधिकारी आणि दुकान ते पाहू शकतात. आम्ही तुमची माहिती कधीही विकत नाही.';

  @override
  String kisanConsentGivenOn(String date) {
    return '$date रोजी दिली';
  }

  @override
  String get kisanConsentIntro =>
      'कृपया वाचा किंवा ऐका. दुसरी निवड तुम्ही कधीही “मी” मध्ये बदलू शकता.';

  @override
  String get kisanConsentOffersNotice =>
      'आम्ही ऑफर आणि शेतीच्या टिप्स SMS किंवा WhatsApp वर पाठवतो. “मी” मध्ये कधीही बंद करू शकता.';

  @override
  String get kisanConsentPending => 'या फोनवर जतन केले. इंटरनेट आल्यावर पाठवू.';

  @override
  String get kisanConsentSettings => 'माझी संमती';

  @override
  String get kisanConsentTitle => 'सुरू करण्यापूर्वी';

  @override
  String kisanConsentWithdrawnOn(String date) {
    return '$date रोजी बंद केले';
  }

  @override
  String get kisanCouldNotOpen => 'उघडता आले नाही. पुन्हा प्रयत्न करा.';

  @override
  String get kisanCreditStoreWillConfirm => 'तुमचे दुकान पक्के करेल';

  @override
  String get kisanCropDoctorSoonHelp =>
      'लवकरच येथे पिकाचा फोटो काढून सल्ला मिळेल.';

  @override
  String get kisanCropDoctorSoonTitle => 'पीक डॉक्टर लवकरच येत आहे';

  @override
  String get kisanCropUnknown => 'पीक';

  @override
  String get kisanDeleteAccount => 'माझे खाते हटवा';

  @override
  String get kisanDeleteAfter =>
      'तोपर्यंत तुम्ही किसान वापरू शकता. मन बदलल्यास तुमच्या दुकानाला फोन करा.';

  @override
  String get kisanDeleteAreYouSure =>
      'नक्की? तुमचे खाते आणि माहिती हटवली जाईल. हे परत येणार नाही.';

  @override
  String kisanDeleteDueBy(String date) {
    return '$date पर्यंत पूर्ण करू';
  }

  @override
  String get kisanDeleteExplain =>
      'आम्ही तुमचे खाते, शेताची माहिती, पिकाचे फोटो आणि संदेश हटवू. बिलांसारख्या कायद्याने ठेवायच्या नोंदी काही काळ ठेवून नंतर हटवल्या जातील.';

  @override
  String get kisanDeleteKeep => 'नको, माझे खाते ठेवा';

  @override
  String get kisanDeleteKeepsDues =>
      'खाते हटवल्यानंतरही दुकानाची बाकी भरावी लागेल.';

  @override
  String kisanDeleteRequested(String ticket) {
    return 'विनंती पाठवली · $ticket';
  }

  @override
  String get kisanDeleteStatusCompleted => 'तुमचे खाते हटवले आहे';

  @override
  String get kisanDeleteStatusInProgress => 'आम्ही तुमची माहिती हटवत आहोत';

  @override
  String get kisanDeleteStatusReceived => 'तुमची विनंती मिळाली';

  @override
  String kisanDeleteTicket(String ticket) {
    return 'तिकीट $ticket';
  }

  @override
  String get kisanDeleteYes => 'होय, हटवा';

  @override
  String get kisanDelivery => 'घरी पोहोचवा';

  @override
  String kisanDuesTitle(String amount) {
    return 'तुमची बाकी $amount';
  }

  @override
  String get kisanFarmUnnamed => 'माझे शेत';

  @override
  String get kisanFieldOfficer => 'फील्ड अधिकारी';

  @override
  String get kisanGoToPay => 'पैसे भरायला चला';

  @override
  String kisanGreeting(String name) {
    return 'नमस्कार, $name';
  }

  @override
  String get kisanGreetingNoName => 'नमस्कार';

  @override
  String get kisanHelpCallStore => 'मदत: दुकानाला फोन करा';

  @override
  String get kisanHelpNoPhone => 'दुकानाचा फोन अजून नाही';

  @override
  String get kisanHowMany => 'किती हवे?';

  @override
  String get kisanHowPay => 'पैसे कसे भरणार?';

  @override
  String kisanInStock(String count) {
    return 'तुमच्या दुकानात $count आहेत';
  }

  @override
  String get kisanIrrigationQuestion => 'शेताला पाणी कसे देता?';

  @override
  String get kisanIrrigationUnknown => 'पाणी: माहीत नाही';

  @override
  String get kisanItems => 'माल';

  @override
  String get kisanKhataNotLoaded => 'खाते अजून या फोनवर नाही';

  @override
  String get kisanLess => 'कमी';

  @override
  String get kisanMore => 'जास्त';

  @override
  String get kisanMyCrops => 'माझी पिके';

  @override
  String get kisanMyOfficer => 'माझे फील्ड अधिकारी';

  @override
  String get kisanMyOrders => 'माझ्या ऑर्डर';

  @override
  String get kisanNavCropDoctor => 'पीक डॉक्टर';

  @override
  String get kisanNavHome => 'मुख्य';

  @override
  String get kisanNavMe => 'मी';

  @override
  String get kisanNavOrders => 'ऑर्डर';

  @override
  String get kisanNeedsInternet =>
      'यासाठी इंटरनेट हवे. इंटरनेट आल्यावर पुन्हा प्रयत्न करा.';

  @override
  String get kisanNextTaskSoon => 'पुढचे काम: लवकरच';

  @override
  String get kisanNo => 'नाही';

  @override
  String get kisanNoAlerts => 'तुमच्या भागात किडीचा इशारा नाही';

  @override
  String get kisanNoCropsHelp =>
      'तुमचे फील्ड अधिकारी किंवा दुकान तुमचे शेत जोडू शकतात.';

  @override
  String get kisanNoCropsYet => 'अजून पिके नाहीत';

  @override
  String get kisanNotifications => 'सूचना';

  @override
  String get kisanNotPaidYet =>
      'अजून पैसे भरले नाहीत. नंतर किंवा दुकानात भरू शकता.';

  @override
  String get kisanOff => 'बंद';

  @override
  String get kisanOffersOff => 'ऑफर आणि टिप्स: बंद';

  @override
  String get kisanOffersOn => 'ऑफर आणि टिप्स: चालू';

  @override
  String get kisanOfficerPhoneMissing =>
      'अधिकाऱ्यांचा फोन अजून ॲपमध्ये नाही. तुमच्या दुकानात विचारा.';

  @override
  String get kisanOn => 'चालू';

  @override
  String get kisanOrderCollected => 'घेतले';

  @override
  String get kisanOrderNotSaved => 'ही ऑर्डर अजून या फोनवर नाही';

  @override
  String get kisanOrderOnKhata => 'तुमच्या खात्यावर लिहिले';

  @override
  String get kisanOrderPaid => 'पैसे भरले';

  @override
  String get kisanOrderPlaced => 'ऑर्डर झाली';

  @override
  String get kisanOrdersEmptyHelp =>
      'दुकानातून ऑर्डर करण्यासाठी माल खरेदी करा दाबा.';

  @override
  String get kisanOrderShort => 'दुकानात एक माल पुरेसा नाही. संख्या बदला.';

  @override
  String get kisanOrderTitle => 'माझी ऑर्डर';

  @override
  String get kisanOutOfStock => 'आता स्टॉकमध्ये नाही';

  @override
  String kisanPaidOn(String time) {
    return '$time रोजी भरले';
  }

  @override
  String get kisanPaidThanks => 'पैसे भरले. धन्यवाद!';

  @override
  String get kisanPayAtStore => 'दुकानात भरेन';

  @override
  String get kisanPayAtStoreHelp => 'माल घेताना रोख किंवा UPI';

  @override
  String get kisanPayAtStoreNote => 'घेताना दुकानात पैसे भरा';

  @override
  String get kisanPayCredit => 'उधार मागा';

  @override
  String get kisanPaymentDone => 'पैसे मिळाले';

  @override
  String get kisanPaymentFailed => 'पैसे भरले गेले नाहीत. पैसे कापले नाहीत.';

  @override
  String kisanPaymentRef(String ref) {
    return 'संदर्भ: $ref';
  }

  @override
  String get kisanPayTitle => 'पैसे भरा';

  @override
  String get kisanPayUpi => 'UPI ने पैसे भरा';

  @override
  String get kisanPayUpiHelp => 'PhonePe, Google Pay किंवा तुमचे UPI ॲप उघडेल';

  @override
  String get kisanPickup => 'दुकानातून घेईन';

  @override
  String get kisanPickupQuestion => 'तुम्ही कसे घेणार?';

  @override
  String kisanPlacedOn(String time) {
    return '$time रोजी ऑर्डर केली';
  }

  @override
  String get kisanPlaceOrder => 'ऑर्डर करा';

  @override
  String get kisanProductTitle => 'माल';

  @override
  String get kisanRateQuestion => 'भेट कशी होती?';

  @override
  String get kisanRateTitle => 'भेटीला रेटिंग द्या';

  @override
  String get kisanRateWhy => 'का?';

  @override
  String get kisanReasonAdviceUnclear => 'सल्ला समजला नाही';

  @override
  String get kisanReasonDidNotSeeCrop => 'माझे पीक पाहिले नाही';

  @override
  String get kisanReasonLookedAtCrop => 'माझे पीक पाहिले';

  @override
  String get kisanReasonOnTime => 'वेळेवर आले';

  @override
  String get kisanReasonTooShort => 'खूप कमी वेळ थांबले';

  @override
  String get kisanReasonUsefulAdvice => 'उपयोगी सल्ला';

  @override
  String get kisanReceiptTitle => 'पावती';

  @override
  String get kisanSave => 'जतन करा';

  @override
  String get kisanSaved => 'जतन केले';

  @override
  String get kisanSavedWillSend => 'जतन केले. इंटरनेट आल्यावर पाठवू.';

  @override
  String get kisanSaveFailed => 'जतन झाले नाही. पुन्हा प्रयत्न करा.';

  @override
  String get kisanScanButton => 'QR स्कॅन करा';

  @override
  String get kisanScanHelp =>
      'तुमच्या फील्ड अधिकाऱ्यांना त्यांच्या फोनवर QR दाखवायला सांगा, मग तो स्कॅन करा.';

  @override
  String get kisanScanNotVisitQr =>
      'हा भेटीचा QR नाही. अधिकाऱ्यांच्या फोनवरील QR स्कॅन करा.';

  @override
  String get kisanScanTitle => 'भेटीचा QR स्कॅन करा';

  @override
  String get kisanScanVisitQr => 'भेट QR';

  @override
  String get kisanSend => 'पाठवा';

  @override
  String get kisanSetupCropQuestion => 'कोणते पीक घेता?';

  @override
  String get kisanSetupLandQuestion => 'किती जमीन?';

  @override
  String get kisanSetupNoVillages =>
      'गावांची यादी अजून या फोनवर नाही. तुमचे दुकान जोडेल.';

  @override
  String get kisanSetupSownQuestion => 'पेरणी कधी केली?';

  @override
  String get kisanSetupVillageQuestion => 'तुमचे गाव';

  @override
  String get kisanShopEmptyHelp => 'दुसऱ्या प्रकारचा माल पाहा.';

  @override
  String get kisanShopHelp => 'माल पाहण्यासाठी आणि टोपलीत टाकण्यासाठी तो दाबा.';

  @override
  String get kisanSkipForNow => 'आत्ता वगळा';

  @override
  String get kisanSoilQuestion => 'तुमची माती कोणती?';

  @override
  String get kisanSoilUnknown => 'माती: माहीत नाही';

  @override
  String get kisanSownLonger => '3 महिने किंवा जास्त';

  @override
  String get kisanSownThisMonth => 'या महिन्यात';

  @override
  String get kisanSownThisWeek => 'या आठवड्यात';

  @override
  String get kisanSownTwoMonths => '1–2 महिन्यांपूर्वी';

  @override
  String kisanStageIs(String stage) {
    return 'अवस्था: $stage';
  }

  @override
  String get kisanStageQuestion => 'पीक कोणत्या अवस्थेत आहे?';

  @override
  String get kisanStageUnknown => 'अवस्था: माहीत नाही';

  @override
  String get kisanTotalEstimateNote => 'अंतिम किंमत दुकान सांगेल.';

  @override
  String kisanTotalToPay(String amount) {
    return 'एकूण $amount';
  }

  @override
  String get kisanUpiNoApp =>
      'कोणतेही UPI ॲप उघडले नाही. UPI ॲप घ्या किंवा दुकानात पैसे भरा.';

  @override
  String get kisanUpiOpenAgain => 'UPI ॲप पुन्हा उघडा';

  @override
  String get kisanUpiWaiting => 'तुमच्या UPI ॲपमध्ये पैसे भरणे पूर्ण करा';

  @override
  String get kisanViewCart => 'टोपली पाहा';

  @override
  String get kisanVisitAlreadyAnswered =>
      'या भेटीचे उत्तर तुम्ही आधीच दिले आहे.';

  @override
  String get kisanVisitNoThanks => 'धन्यवाद. आम्ही अधिकाऱ्यांशी बोलू.';

  @override
  String kisanVisitQuestion(String name) {
    return 'आज $name तुमच्या शेतावर आले होते का?';
  }

  @override
  String get kisanVisitQuestionNoName =>
      'आज तुमचे फील्ड अधिकारी तुमच्या शेतावर आले होते का?';

  @override
  String get kisanVisitTapToAnswer => 'उत्तर देण्यासाठी दाबा';

  @override
  String get kisanVisitThanks => 'धन्यवाद! भेट पक्की झाली.';

  @override
  String get kisanVisitTitle => 'फील्ड अधिकारी भेट';

  @override
  String get kisanVisitTokenInvalid =>
      'या प्रश्नाची मुदत संपली. अधिकाऱ्यांना QR दाखवायला सांगा.';

  @override
  String get kisanWeatherSoon => 'तुमच्या शेताचे हवामान लवकरच येईल';

  @override
  String get kisanWelcomeChange => 'काहीतरी चूक आहे: बदला';

  @override
  String get kisanWelcomeConfirmHelp => 'कृपया तुमचे शेत आणि पिके तपासा.';

  @override
  String get kisanWelcomeCorrect => 'होय, हे बरोबर आहे';

  @override
  String get kisanWelcomeEditHelp => 'बदलण्यासाठी चित्र दाबा.';

  @override
  String kisanWelcomeFromOfficer(String name) {
    return '$name (फील्ड अधिकारी) यांच्याकडून तुमच्या शेताची माहिती';
  }

  @override
  String get kisanWelcomeFromYourOfficer =>
      'तुमच्या फील्ड अधिकाऱ्यांकडून तुमच्या शेताची माहिती';

  @override
  String get kisanWelcomeTitle => 'स्वागत आहे';

  @override
  String get kisanWhatsApp => 'WhatsApp';

  @override
  String get kisanYes => 'होय';

  @override
  String get kisanYourOfficer => 'तुमचे फील्ड अधिकारी';

  @override
  String get photoTipNotPlant =>
      'कॅमेरा आजारी पानाकडे धरा आणि पुन्हा फोटो काढा';

  @override
  String get photoQualityNotPlant => 'पान दिसले नाही';

  @override
  String get treatmentPpeClothing => 'पूर्ण बाह्यांचे कपडे';

  @override
  String get cropDoctorTitle => 'पीक डॉक्टर';

  @override
  String get cropDoctorIntroTitle => 'आजारी पानाचा फोटो काढा';

  @override
  String get cropDoctorIntroTip1 => 'एका आजारी पानाजवळ जा';

  @override
  String get cropDoctorIntroTip2 => 'सूर्य तुमच्या पाठीमागे ठेवून उभे राहा';

  @override
  String get cropDoctorIntroTip3 =>
      'फोन स्थिर धरा आणि पानावर टॅप करून फोकस करा';

  @override
  String get cropDoctorUpTo3 => 'तुम्ही 3 फोटोपर्यंत काढू शकता';

  @override
  String get cropDoctorOpenCamera => 'कॅमेरा उघडा';

  @override
  String get cropDoctorTakePhoto => 'फोटो काढा';

  @override
  String get cropDoctorCameraDenied =>
      'पिकाचा फोटो काढण्यासाठी कॅमेऱ्याला परवानगी द्या';

  @override
  String get cropDoctorCameraError => 'कॅमेरा उघडला नाही. पुन्हा प्रयत्न करा.';

  @override
  String get cropDoctorTryAgain => 'पुन्हा प्रयत्न करा';

  @override
  String cropDoctorPhotoCount(int count) {
    return 'फोटो $count / 3';
  }

  @override
  String cropDoctorPhotosReady(int count) {
    return '3 पैकी $count फोटो तयार';
  }

  @override
  String get cropDoctorAddPhoto => 'आणखी एक फोटो काढा';

  @override
  String get cropDoctorRemovePhoto => 'फोटो काढून टाका';

  @override
  String get cropDoctorCheckCrop => 'माझे पीक तपासा';

  @override
  String get cropDoctorChooseCropTitle => 'हे कोणते पीक आहे?';

  @override
  String cropDoctorDetected(String crop) {
    return 'हे $crop वाटते. चुकीचे असल्यास दुसरे पीक दाबा.';
  }

  @override
  String cropDoctorCropIs(String crop) {
    return 'पीक: $crop';
  }

  @override
  String get cropDoctorChangeCrop => 'पीक बदला';

  @override
  String get cropDoctorUnknownCrop => 'मला माहीत नाही';

  @override
  String get cropDoctorAskExpertToo => 'आमच्या तज्ज्ञालाही विचारा';

  @override
  String get cropDoctorAnalysing => 'तुमचे पीक तपासत आहोत…';

  @override
  String get cropDoctorAnalysingHelp => 'याला काही सेकंद लागतात';

  @override
  String get cropDoctorQueuedTitle => 'तुमच्या फोनमध्ये सेव्ह झाले';

  @override
  String get cropDoctorQueuedHelp => 'इंटरनेट आल्यावर आम्ही तपासू';

  @override
  String get cropDoctorSendFailed =>
      'तुमचे फोटो पाठवता आले नाहीत. पुन्हा काढा.';

  @override
  String get cropDoctorResultTitle => 'निकाल';

  @override
  String get cropDoctorMessageAnswered => 'आम्हाला समस्या सापडली';

  @override
  String get cropDoctorMessageProvisional => 'तात्पुरते — तज्ज्ञ खात्री करतील';

  @override
  String get cropDoctorMessageUnknown =>
      'अजून खात्री नाही. आमचे तज्ज्ञ तुमचे फोटो पाहतील.';

  @override
  String get cropDoctorMessageConfirmed =>
      'आमच्या तज्ज्ञांनी हा निकाल निश्चित केला';

  @override
  String get cropDoctorMessageCorrected => 'आमच्या तज्ज्ञांनी हा निकाल बदलला';

  @override
  String get cropDoctorOutNotPlant => 'फोटोत रोप दिसले नाही';

  @override
  String get cropDoctorOutUnsupportedCrop => 'हे पीक अजून तपासता येत नाही';

  @override
  String get cropDoctorOutUnreadable => 'फोटो स्पष्ट नव्हता';

  @override
  String get cropDoctorOutNoMatch => 'ही समस्या ओळखता आली नाही';

  @override
  String get cropDoctorOutNotDiagnosable =>
      'फोटोवरून तज्ज्ञांना सांगता आले नाही';

  @override
  String get cropDoctorOutHelp =>
      'आमचे तज्ज्ञ हे पाहतील. तुम्ही तुमच्या फील्ड ऑफिसरला फोनही करू शकता.';

  @override
  String get cropDoctorTalkToOfficer => 'तुमच्या फील्ड ऑफिसरशी बोला';

  @override
  String get cropDoctorCallOfficer => 'माझ्या ऑफिसरला फोन';

  @override
  String get cropDoctorAskExpert => 'तज्ज्ञाला विचारा';

  @override
  String get cropDoctorAskExpertSent =>
      'आमच्या तज्ज्ञाला पाठवले. उत्तर तुम्हाला कळवू.';

  @override
  String get cropDoctorAskExpertAlready =>
      'आमच्या तज्ज्ञांकडे तुमचे फोटो आधीच आहेत';

  @override
  String get cropDoctorAskExpertFailed =>
      'आमच्या तज्ज्ञांपर्यंत पोहोचता आले नाही. इंटरनेट तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get cropDoctorOrder => 'ऑर्डर करा';

  @override
  String cropDoctorProductsAt(String store) {
    return '$store येथे मिळणारे';
  }

  @override
  String cropDoctorStoreDistance(String store, String km) {
    return '$store, $km किमी';
  }

  @override
  String get cropDoctorCulturalTitle => 'हेही करा';

  @override
  String get cropDoctorNoProducts =>
      'तुमच्या दुकानात यासाठी अजून उत्पादन नाही. तुमच्या फील्ड ऑफिसरशी बोला.';

  @override
  String get cropDoctorUpdatedTitle => 'तुमचा निकाल बदलला';

  @override
  String get cropDoctorHistoryTitle => 'आधीची उत्तरे';

  @override
  String cropDoctorEarlierAnswer(String answer) {
    return 'आधी: $answer';
  }

  @override
  String get cropDoctorMyChecks => 'माझ्या पीक तपासण्या';

  @override
  String get cropDoctorWaiting => 'उत्तराची वाट';

  @override
  String get cropDoctorSymptomsHelp => 'तुमच्या पिकावर दिसणारी लक्षणे दाबा';

  @override
  String cropDoctorResultUpdatedHome(String problem) {
    return 'पीक तपासणी बदलली: $problem';
  }

  @override
  String get scoutTitle => 'पीक पाहणी';

  @override
  String get scoutChoosePlot => 'पीक प्लॉट निवडा';

  @override
  String get scoutNoPlots =>
      'या शेतकऱ्याचा अजून पीक प्लॉट नाही. आधी शेत आणि पीक जोडा.';

  @override
  String scoutPlotLine(String crop, String farm) {
    return '$crop · $farm';
  }

  @override
  String scoutAttachedTo(String farmer, String crop) {
    return '$farmer साठी · $crop';
  }

  @override
  String get scoutCreateOrder => 'शेतकऱ्यासाठी ऑर्डर करा';

  @override
  String get scoutCallFarmer => 'शेतकऱ्याला फोन';

  @override
  String get scoutQueuedHelp => 'रांगेत आहे. फोन ऑनलाइन झाल्यावर पाठवले जाईल.';

  @override
  String scoutProvenance(String model, String corpus) {
    return 'मॉडेल $model · कॉर्पस v$corpus';
  }

  @override
  String get scoutNewDiagnosis => 'नवीन निदान';

  @override
  String get scoutCheckPhotos => 'फोटो तपासा';

  @override
  String get kisanDeleteStatusRejected =>
      'तुमची विनंती स्वीकारली नाही. कृपया तुमच्या दुकानाला फोन करा.';

  @override
  String get cropDoctorNotOnPhone => 'ही पीक तपासणी या फोनवर नाही';

  @override
  String get voiceStart => 'बोला';

  @override
  String get voiceStop => 'थांबवा';

  @override
  String get voiceListening => 'ऐकत आहे…';

  @override
  String get voiceUnavailable =>
      'या फोनमध्ये व्हॉइस टायपिंग नाही. तुम्ही टाइप करू शकता.';

  @override
  String fieldAsOf(String time) {
    return '$time पर्यंत';
  }

  @override
  String get fieldOfflineCached => 'शेवटची सिंक केलेली प्रत दाखवत आहे.';

  @override
  String get fieldPendingSync => 'सिंक होईल';

  @override
  String get meSectionTitle => 'माझे काम';

  @override
  String get settingsLogOut => 'लॉग आउट';

  @override
  String get settingsLogOutHelp =>
      'पुन्हा साइन इन करण्यासाठी फोन आणि OTP लागेल.';

  @override
  String get inboxTitle => 'सूचना';

  @override
  String get inboxEmpty => 'सूचना नाहीत';

  @override
  String get inboxEmptyHelp => 'भेट पुष्टी, ऑर्डर आणि मंजुरी इथे दिसतील.';

  @override
  String get inboxMarkAllRead => 'सर्व वाचले म्हणून खूण करा';

  @override
  String inboxUnread(int count) {
    return '$count न वाचलेल्या';
  }

  @override
  String get navInbox => 'इनबॉक्स';

  @override
  String get notifBeatPlanReadyTitle => 'आजचा बीट प्लॅन तयार आहे';

  @override
  String get notifBeatPlanReadyBody => 'आजचे शेतकरी पाहण्यासाठी उघडा.';

  @override
  String get notifOrderStatusTitle => 'ऑर्डर अपडेट';

  @override
  String get notifOrderStatusBody => 'दुकानाने ऑर्डरची स्थिती बदलली आहे.';

  @override
  String get notifCreditApprovalTitle => 'उधारीचा निर्णय';

  @override
  String get notifCreditApprovalApproved => 'उधार विक्री मंजूर झाली.';

  @override
  String get notifCreditApprovalRejected => 'उधार विक्री मंजूर झाली नाही.';

  @override
  String get notifTravelClaimSubmittedTitle => 'नवीन खर्च दावा';

  @override
  String get notifTravelClaimSubmittedBody =>
      'एका अधिकाऱ्याने खर्च दावा पाठवला आहे.';

  @override
  String get notifTravelClaimDecidedTitle => 'खर्च दाव्यावर निर्णय';

  @override
  String get notifTravelClaimApproved => 'तुमचा दावा मंजूर झाला.';

  @override
  String get notifTravelClaimRejected => 'तुमचा दावा मंजूर झाला नाही.';

  @override
  String get notifFlagTitle => 'तुमच्या कामावर एक फ्लॅग';

  @override
  String get notifFlagBody => 'स्पष्टीकरण जोडण्यासाठी ‘माझे फ्लॅग’ उघडा.';

  @override
  String get notifDutyAutoEndedBody => 'तुमची ड्युटी आपोआप संपली.';

  @override
  String get notifDiagnosisTitle => 'पीक तपासणी अपडेट';

  @override
  String get notifDiagnosisBody => 'कृषी तज्ज्ञाने पीक तपासणी पाहिली.';

  @override
  String get notifVisitConfirmTitle => 'भेटीची पुष्टी';

  @override
  String get notifVisitConfirmBody => 'शेतकऱ्याची पुष्टी बाकी आहे.';

  @override
  String get notifGenericTitle => 'अपडेट';

  @override
  String get notifGenericBody => 'तपशील पाहण्यासाठी उघडा.';

  @override
  String get beatTitle => 'आजचा बीट';

  @override
  String get beatEmpty => 'अजून बीट प्लॅन नाही';

  @override
  String get beatEmptyHelp =>
      'प्लॅन दररोज सकाळी 6:00 वाजता येतो. तुम्ही स्वतः शेतकरी जोडू शकता.';

  @override
  String beatTarget(int done, int target) {
    return '$target पैकी $done पूर्ण';
  }

  @override
  String get beatReasonFollowUp => 'फॉलो-अप बाकी';

  @override
  String get beatReasonPestAlert => 'कीड इशारा';

  @override
  String get beatReasonCreditDue => 'उधारी बाकी';

  @override
  String get beatReasonDemoStage => 'डेमो टप्पा बाकी';

  @override
  String get beatShowMap => 'नकाशा';

  @override
  String get beatShowList => 'यादी';

  @override
  String get beatAddVillage => 'गाव जोडा';

  @override
  String get beatRemove => 'बीटमधून काढा';

  @override
  String get beatReorderHint => 'क्रम बदलण्यासाठी कार्ड दाबून धरा';

  @override
  String get beatVillageKind => 'गाव';

  @override
  String get myDayGapAddReason => 'कारण जोडा';

  @override
  String get myDayGapSheetTitle => 'अंतर का आहे?';

  @override
  String get myDayGapReasonNetwork => 'नेटवर्क किंवा GPS नाही';

  @override
  String get myDayGapReasonBreak => 'वैयक्तिक विश्रांती';

  @override
  String get myDayGapReasonVehicle => 'वाहनाची अडचण';

  @override
  String get myDayGapReasonOther => 'इतर';

  @override
  String get myDayGapNoteLabel => 'टीप';

  @override
  String get myDayGapNoteHint => 'काय झाले ते सांगा';

  @override
  String myDayGapRange(String start, String end, int minutes) {
    return '$start – $end · $minutes मिनिटे';
  }

  @override
  String get myDayGapReasonSaved => 'कारण जतन केले. ते सिंक होईल.';

  @override
  String get myDayManagerSeesReasons => 'तुमचे क्लस्टर हेड ही कारणे पाहतात.';

  @override
  String get myDayNoGaps => 'आज कोणतेही अंतर नाही';

  @override
  String myDayStops(int count) {
    return '$count थांबे';
  }

  @override
  String myDayVisitPins(int count) {
    return '$count भेटी';
  }

  @override
  String get myDayKmEstimated => 'या फोनवरील अंदाज';

  @override
  String get myDayKmProcessed => 'सर्व्हरने प्रक्रिया केली';

  @override
  String get performanceTitle => 'माझी कामगिरी';

  @override
  String get perfTargetsVsActual => 'लक्ष्य विरुद्ध प्रत्यक्ष';

  @override
  String get perfNewFarmers => 'नवीन शेतकरी';

  @override
  String get perfSales => 'विक्री';

  @override
  String get perfIncentive => 'मिळालेले प्रोत्साहन';

  @override
  String get perfIncentivePending =>
      'कंपनीने प्रोत्साहन नियम सुरू केल्यावर दिसेल.';

  @override
  String get perfTrendTitle => 'पडताळलेल्या भेटी, मागील 14 दिवस';

  @override
  String perfOfTarget(String actual, String target) {
    return '$target पैकी $actual';
  }

  @override
  String get perfNoTarget => 'लक्ष्य ठरवलेले नाही';

  @override
  String perfRank(int rank) {
    return 'तुमच्या क्लस्टरमध्ये $rankवे स्थान';
  }

  @override
  String get perfConfirmationRate => 'शेतकरी पुष्टी';

  @override
  String get perfEmpty => 'या महिन्यात अजून काही नाही';

  @override
  String get perfEmptyHelp => 'भेटी आणि ऑर्डर सिंक झाल्यावर आकडे दिसतील.';

  @override
  String get travelTitle => 'प्रवास भत्ता';

  @override
  String get travelKmByDay => 'दिवसानुसार किमी';

  @override
  String get travelTaTotal => 'किमीवरून भत्ता';

  @override
  String get travelPayable => 'आतापर्यंत देय';

  @override
  String travelCapped(int cap) {
    return '$cap किमी पर्यंत मर्यादित';
  }

  @override
  String travelDayKm(String km) {
    return '$km किमी';
  }

  @override
  String get travelClaimsTitle => 'खर्च दावे';

  @override
  String get travelAddClaim => 'खर्च जोडा';

  @override
  String get travelClaimType => 'प्रकार';

  @override
  String get travelClaimTypeFuel => 'इंधन';

  @override
  String get travelClaimTypeBus => 'बस भाडे';

  @override
  String get travelClaimTypeOther => 'इतर';

  @override
  String get travelClaimAmount => 'रक्कम';

  @override
  String get travelClaimDate => 'खर्चाची तारीख';

  @override
  String get travelClaimNote => 'टीप';

  @override
  String get travelClaimReceipt => 'पावतीचा फोटो';

  @override
  String get travelClaimTakePhoto => 'पावतीचा फोटो घ्या';

  @override
  String get travelClaimReceiptRequired => 'पावतीचा फोटो आवश्यक आहे.';

  @override
  String get travelClaimAmountRequired => 'रक्कम टाका.';

  @override
  String get travelClaimQueued => 'दावा जतन केला. तो सिंक होईल.';

  @override
  String get travelClaimStatusQueued => 'सिंकची वाट';

  @override
  String get travelClaimStatusSubmitted => 'क्लस्टर हेडकडे';

  @override
  String get travelClaimStatusApproved => 'मंजूर';

  @override
  String get travelClaimStatusRejected => 'मंजूर नाही';

  @override
  String get travelEmpty => 'या महिन्यात अजून प्रवास नाही';

  @override
  String get travelEmptyHelp => 'ड्युटीवर जा; किमी आणि भत्ता इथे दिसेल.';

  @override
  String get flagsTitle => 'माझे फ्लॅग';

  @override
  String get flagsOpenSection => 'खुले';

  @override
  String get flagsResolvedSection => 'निकाली गेलेली';

  @override
  String get flagsEmpty => 'तुमच्या कामावर फ्लॅग नाहीत';

  @override
  String get flagsEmptyHelp => 'तुम्ही फक्त स्वतःबद्दलचे फ्लॅग पाहता.';

  @override
  String get flagAddExplanation => 'स्पष्टीकरण जोडा';

  @override
  String get flagExplanationLabel => 'तुमचे स्पष्टीकरण';

  @override
  String get flagExplanationHint => 'त्या दिवशी काय झाले ते सांगा';

  @override
  String get flagExplanationSent => 'क्लस्टर हेडला पाठवले.';

  @override
  String get flagExplanationNeedsNetwork =>
      'स्पष्टीकरण पाठवण्यासाठी नेटवर्क कनेक्शन हवे.';

  @override
  String get flagOutcomeTitle => 'निकाल';

  @override
  String get flagOutcomeHidden => 'हा फ्लॅग निकाली निघाल्यावर निकाल दिसेल.';

  @override
  String get flagStateOpen => 'खुला';

  @override
  String get flagStateInReview => 'पुनरावलोकनात';

  @override
  String get flagStateResolved => 'निकाली';

  @override
  String get flagSeverityLow => 'कमी';

  @override
  String get flagSeverityMedium => 'मध्यम';

  @override
  String get flagSeverityHigh => 'जास्त';

  @override
  String get meetingsTitle => 'शेतकरी बैठका';

  @override
  String get meetingsEmpty => 'अजून बैठका नाहीत';

  @override
  String get meetingsEmptyHelp => 'गावाच्या बैठक ठिकाणी सुरू करा.';

  @override
  String get meetingNew => 'नवीन बैठक';

  @override
  String get meetingTopic => 'विषय';

  @override
  String get meetingTopicHint => 'बैठक कशाबद्दल आहे';

  @override
  String get meetingNotes => 'बैठकीच्या नोंदी';

  @override
  String get meetingStart => 'बैठक सुरू करा';

  @override
  String get meetingAttendance => 'उपस्थिती';

  @override
  String meetingAttendees(int count) {
    return '$count उपस्थित';
  }

  @override
  String get meetingAddByOtp => 'OTP ने जोडा';

  @override
  String get meetingAddByQr => 'शेतकरी QR स्कॅन करा';

  @override
  String meetingOtpSent(String phone) {
    return '$phone वर कोड पाठवला';
  }

  @override
  String get meetingOtpNeedsNetwork =>
      'OTP साठी नेटवर्क हवे. त्याऐवजी QR वापरा.';

  @override
  String get meetingFinish => 'बैठक संपवा';

  @override
  String get meetingClosed => 'बंद';

  @override
  String get meetingQrInvalid => 'तो QR शेतकरी उपस्थिती कोड नाही.';

  @override
  String get meetingAlreadyPresent => 'तो शेतकरी आधीच यादीत आहे.';

  @override
  String get demoTitle => 'डेमो प्लॉट';

  @override
  String get demoEmpty => 'अजून डेमो प्लॉट नाहीत';

  @override
  String get demoEmptyHelp => 'शेतकऱ्याच्या पीक प्लॉटवर नोंदवा.';

  @override
  String get demoNew => 'नवीन डेमो प्लॉट';

  @override
  String get demoTreatment => 'उत्पादन किंवा उपचार';

  @override
  String get demoBaseline => 'कशाशी तुलना करावी';

  @override
  String get demoBaselinePractice => 'शेतकऱ्याची पद्धत';

  @override
  String get demoBaselineComparison => 'तुलना प्लॉट';

  @override
  String get demoStatusCreated => 'नोंदवलेले';

  @override
  String get demoStatusActive => 'सुरू आहे';

  @override
  String get demoStatusHarvested => 'कापणी झाली';

  @override
  String get demoStatusReported => 'अहवाल दिला';

  @override
  String get demoStageSown => 'पेरणी';

  @override
  String get demoStageVegetative => 'वाढीचा';

  @override
  String get demoStageFlowering => 'फुलोरा';

  @override
  String get demoStageFruiting => 'फळधारणा';

  @override
  String get demoStageMaturity => 'परिपक्वता';

  @override
  String get demoStageHarvest => 'कापणी';

  @override
  String get demoAddObservation => 'टप्पा निरीक्षण जोडा';

  @override
  String get demoObservationNote => 'निरीक्षण';

  @override
  String get demoSide => 'बाजू';

  @override
  String get demoSideDemo => 'डेमो';

  @override
  String get demoSideBoth => 'दोन्ही';

  @override
  String get demoTakePhoto => 'टप्प्याचा फोटो जोडा';

  @override
  String get demoEnterYield => 'उत्पादन नोंदवा';

  @override
  String get demoYieldDemo => 'डेमो उत्पादन (किग्रॅ/एकर)';

  @override
  String get demoYieldPractice => 'शेतकरी पद्धत उत्पादन (किग्रॅ/एकर)';

  @override
  String demoYieldGain(String pct) {
    return 'शेतकरी पद्धतीपेक्षा $pct% जास्त';
  }

  @override
  String get demoStart => 'डेमो सुरू करा';

  @override
  String get demoReport => 'अहवाल दिला म्हणून खूण करा';

  @override
  String get demoComparison => 'डेमो विरुद्ध शेतकरी पद्धत';

  @override
  String get visitVoiceInputSoon => 'व्हॉइस इनपुट पुढील अपडेटमध्ये येईल';

  @override
  String get kisanAddCrop => 'पीक जोडा';

  @override
  String get kisanCropCalendar => 'पीक दिनदर्शिका';

  @override
  String get kisanWeather => 'हवामान';

  @override
  String get kisanAlerts => 'कीड इशारे';

  @override
  String get kisanMessages => 'संदेश';

  @override
  String get addCropTitle => 'पीक जोडा';

  @override
  String get addCropHelp => 'चित्रांना स्पर्श करा. टाइप करण्याची गरज नाही.';

  @override
  String get addCropWhichCrop => 'तुम्ही कोणते पीक पेरले?';

  @override
  String get addCropWhichFarm => 'कोणते शेत?';

  @override
  String get addCropWhenSown => 'कधी पेरले?';

  @override
  String get addCropWater => 'पाणी कसे देता?';

  @override
  String get addCropSoil => 'कोणती माती आहे?';

  @override
  String get addCropSave => 'पीक जतन करा';

  @override
  String get addCropSaved => 'पीक जोडले. तुमची दिनदर्शिका तयार आहे.';

  @override
  String addCropSownOn(String date) {
    return '$date रोजी पेरले';
  }

  @override
  String get addCropNoFarm => 'आधी तुमचे शेत जोडा';

  @override
  String get calendarTitle => 'पीक दिनदर्शिका';

  @override
  String get calendarHelp =>
      'आठवड्यानुसार तुमची कामे. ऐकण्यासाठी स्पीकरला स्पर्श करा.';

  @override
  String calendarWeek(int week) {
    return 'आठवडा $week';
  }

  @override
  String calendarSownOn(String date) {
    return '$date रोजी पेरले';
  }

  @override
  String calendarDueOn(String date) {
    return '$date रोजी करा';
  }

  @override
  String calendarDueBetween(String from, String to) {
    return '$from ते $to दरम्यान करा';
  }

  @override
  String get calendarLate => 'उशीर झाला';

  @override
  String get calendarMarkDone => 'झाले म्हणून खूण करा';

  @override
  String get calendarDone => 'झाले';

  @override
  String get calendarRemindMe => 'आठवण करा';

  @override
  String get calendarReminderOff => 'आठवण नको';

  @override
  String get calendarNoTasks => 'अजून कामे नाहीत';

  @override
  String get calendarNoTasksHelp => 'पेरणीची तारीख जोडा, कामे येतील.';

  @override
  String get calendarChangedTitle => 'तुमची दिनदर्शिका बदलली';

  @override
  String calendarChangedLater(int days, int count) {
    return 'पेरणीची तारीख $days दिवस पुढे गेली, म्हणून $count कामेही पुढे गेली.';
  }

  @override
  String calendarChangedEarlier(int days, int count) {
    return 'पेरणीची तारीख $days दिवस आधी आली, म्हणून $count कामेही आधी आली.';
  }

  @override
  String calendarChangedTasks(int count) {
    return '$count कामे बदलली.';
  }

  @override
  String get calendarChangedDoneKept => 'तुम्ही आधीच केलेले काम झालेलेच राहील.';

  @override
  String get calendarGotIt => 'समजले';

  @override
  String calendarNextTask(String task) {
    return 'पुढे: $task';
  }

  @override
  String get calendarAllDone => 'सर्व कामे झाली';

  @override
  String get calendarSavedOffline =>
      'या फोनमध्ये जतन केले. ऑनलाइन झाल्यावर पाठवू.';

  @override
  String get taskTypeSow => 'पेरणी';

  @override
  String get taskTypeIrrigate => 'पाणी';

  @override
  String get taskTypeFertilise => 'खत';

  @override
  String get taskTypeSpray => 'फवारणी';

  @override
  String get taskTypeHarvest => 'कापणी';

  @override
  String get weatherTitle => 'हवामान';

  @override
  String get weatherSevenDays => 'पुढचे 7 दिवस';

  @override
  String weatherRainChance(int percent) {
    return 'पाऊस $percent%';
  }

  @override
  String weatherTempRange(String min, String max) {
    return '$min° ते $max°';
  }

  @override
  String weatherWind(String speed) {
    return 'वारा $speed किमी/तास';
  }

  @override
  String get weatherSprayTitle => 'कधी फवारणी करावी';

  @override
  String get weatherSprayNextDays => 'पुढचे 3 दिवस';

  @override
  String get weatherSprayGood => 'फवारणीसाठी चांगली वेळ';

  @override
  String get weatherSprayAvoid => 'फवारणी करू नका';

  @override
  String get weatherSprayNone => 'पुढच्या 3 दिवसांत फवारणीसाठी चांगली वेळ नाही';

  @override
  String weatherWindowTime(String from, String to) {
    return '$from ते $to';
  }

  @override
  String get weatherReasonRainLikely => 'पाऊस येऊ शकतो';

  @override
  String get weatherReasonRain => 'पाऊस पडेल';

  @override
  String get weatherReasonWindHigh => 'वारा खूप जोरात आहे';

  @override
  String get weatherCautionHeat => 'खूप उष्ण';

  @override
  String get weatherCautionHumidityHigh => 'खूप दमट';

  @override
  String get weatherCautionHumidityLow => 'हवा खूप कोरडी आहे';

  @override
  String get weatherAdviceOnly =>
      'हा फक्त सल्ला आहे. फवारणीपूर्वी तुमचे शेत पाहा.';

  @override
  String get weatherNone => 'अजून तुमच्या शेताचे हवामान नाही';

  @override
  String get weatherNoneHelp =>
      'तुमचा फील्ड अधिकारी तुमचे शेत नकाशावर टाकू शकतो.';

  @override
  String get weatherSkyClear => 'स्वच्छ';

  @override
  String get weatherSkyCloudy => 'ढगाळ';

  @override
  String get weatherSkyFog => 'धुके';

  @override
  String get weatherSkyDrizzle => 'हलका पाऊस';

  @override
  String get weatherSkyRain => 'पाऊस';

  @override
  String get weatherSkyShowers => 'जोरदार सरी';

  @override
  String get weatherSkyThunder => 'गडगडाटी वादळ';

  @override
  String get alertsTitle => 'कीड इशारे';

  @override
  String get alertsNone => 'तुमच्या जिल्ह्यात इशारे नाहीत';

  @override
  String get alertsNoneHelp => 'तुमच्या जवळ समस्या पसरली तर आम्ही सांगू.';

  @override
  String get alertSeverityHigh => 'जास्त';

  @override
  String get alertSeverityMedium => 'मध्यम';

  @override
  String get alertSeverityLow => 'कमी';

  @override
  String get alertGrowsCrop => 'तुम्ही हे पीक घेता';

  @override
  String alertFarmersAffected(int count) {
    return '$count शेतकरी बाधित';
  }

  @override
  String alertWeekOf(String date) {
    return '$date चा आठवडा';
  }

  @override
  String get alertLookForTitle => 'काय पाहावे';

  @override
  String get alertDoTitle => 'काय करावे';

  @override
  String get alertCheckCrop => 'माझ्या पिकाचा फोटो घ्या';

  @override
  String get alertSeeProducts => 'दुकानातील उत्पादने पाहा';

  @override
  String get alertDismiss => 'हा इशारा लपवा';

  @override
  String get alertHidden => 'इशारा लपवला';

  @override
  String get alertSignPestUnderLeaf => 'पानांखाली कीड किंवा अंडी आहेत का पाहा';

  @override
  String get alertSignPestHoles => 'पानांना छिद्रे किंवा कुरतडलेल्या कडा पाहा';

  @override
  String get alertSignPestWilting => 'कोमेजलेल्या किंवा सुकणाऱ्या फांद्या पाहा';

  @override
  String get alertSignDiseaseSpots => 'पानांवर डाग पाहा';

  @override
  String get alertSignDiseasePowder => 'पानांवर पांढरी किंवा करडी पावडर पाहा';

  @override
  String get alertSignDiseaseRot => 'कुजलेली खोडे किंवा फळे पाहा';

  @override
  String get alertSignDeficiencyColour => 'पिवळी किंवा फिकट पाने पाहा';

  @override
  String get alertSignDeficiencyGrowth => 'मंद वाढ किंवा लहान पाने पाहा';

  @override
  String get alertSignWeedPatches => 'रोपांमध्ये तण पाहा';

  @override
  String get alertSignWalkField => 'शेतात फिरून 10 रोपे पाहा';

  @override
  String get farmerInboxTitle => 'संदेश';

  @override
  String get farmerInboxEmpty => 'अजून संदेश नाहीत';

  @override
  String get farmerInboxEmptyHelp =>
      'पीक तपासणीचे निकाल, ऑर्डर आणि इशारे येथे येतील.';

  @override
  String get farmerInboxMarkAllRead => 'सर्व वाचले म्हणून खूण करा';

  @override
  String farmerInboxUnread(int count) {
    return '$count नवीन';
  }

  @override
  String get notifDiagnosisReadyTitle => 'तुमची पीक तपासणी तयार आहे';

  @override
  String get notifDiagnosisReadyBody =>
      'समस्या आणि उपाय पाहण्यासाठी स्पर्श करा.';

  @override
  String get notifDiagnosisReviewedTitle =>
      'आमच्या तज्ज्ञाने तुमचा फोटो पाहिला';

  @override
  String get notifDiagnosisReviewedBody =>
      'उत्तर बदलले आहे. वाचण्यासाठी स्पर्श करा.';

  @override
  String get notifDiagnosisExpertTitle => 'तज्ज्ञ तुमचा फोटो पाहत आहेत';

  @override
  String get notifDiagnosisExpertBody => '24 तासांत सांगू.';

  @override
  String get farmerNotifOrderStatusTitle => 'तुमची ऑर्डर पुढे गेली';

  @override
  String get farmerNotifOrderStatusBody =>
      'तुमची ऑर्डर पाहण्यासाठी स्पर्श करा.';

  @override
  String get notifOutbreakAlertTitle => 'तुमच्या जिल्ह्यात कीड इशारा';

  @override
  String get notifOutbreakAlertBody => 'आजच तुमचे शेत पाहा.';

  @override
  String get notifCropTaskReminderTitle => 'आज एक काम आहे';

  @override
  String get notifCropTaskReminderBody =>
      'तुमची पीक दिनदर्शिका उघडण्यासाठी स्पर्श करा.';

  @override
  String get farmerNotifVisitConfirmTitle => 'तुमचा अधिकारी आला होता का?';

  @override
  String get farmerNotifVisitConfirmBody =>
      'होय किंवा नाही सांगण्यासाठी स्पर्श करा.';

  @override
  String get farmerNotifGenericTitle => 'नवीन माहिती';

  @override
  String get farmerNotifGenericBody => 'पाहण्यासाठी स्पर्श करा.';

  @override
  String get mandiTitle => 'मंडी भाव';

  @override
  String get mandiOpen => 'मंडी भाव';

  @override
  String get mandiEmptyTitle => 'अजून भाव नाहीत';

  @override
  String get mandiEmptyHelp =>
      'बाजाराने भाव जाहीर केल्यावर तुमच्या पिकांचे भाव इथे दिसतील.';

  @override
  String get mandiIndicative =>
      'हे भाव फक्त माहितीसाठी आहेत. ते सरकारी बाजार यादीतून येतात, दुकानातून नाही.';

  @override
  String mandiSource(String source) {
    return '$source कडून';
  }

  @override
  String mandiPriceOn(String date) {
    return '$date चा भाव';
  }

  @override
  String get mandiPerQuintal => 'प्रति क्विंटल';

  @override
  String mandiRange(String low, String high) {
    return '$low ते $high';
  }

  @override
  String get mandiNoPriceYet => 'या पिकाचा भाव अजून नाही';

  @override
  String get referralTitle => 'शेतकऱ्याला बोलवा';

  @override
  String get referralOpen => 'शेतकऱ्याला बोलवा';

  @override
  String get referralIntro =>
      'तुमच्या ओळखीच्या शेतकऱ्याला तुमचा कोड पाठवा. ते जोडले की तुम्हाला आणि तुमच्या जवळच्या दुकानाला बक्षीस मिळेल.';

  @override
  String get referralYourCode => 'तुमचा कोड';

  @override
  String get referralShareWhatsApp => 'व्हॉट्सअ‍ॅपवर पाठवा';

  @override
  String get referralShareSms => 'SMS ने पाठवा';

  @override
  String referralShareMessage(String link, String code) {
    return 'पीक सल्ला आणि शेती सामानासाठी किसानवर माझ्यासोबत या. $link उघडा किंवा माझा कोड $code वापरा.';
  }

  @override
  String referralInvited(int count) {
    return '$count बोलावले';
  }

  @override
  String referralJoined(int count) {
    return '$count जोडले';
  }

  @override
  String referralRewarded(int count) {
    return '$count ना बक्षीस';
  }

  @override
  String get referralRewardNone => 'बक्षीस काय आहे ते तुमचे दुकान सांगेल.';

  @override
  String get referralOff => 'सध्या आमंत्रणे बंद आहेत.';

  @override
  String get referralClaimed => 'धन्यवाद. तुमचे आमंत्रण मोजले गेले.';

  @override
  String get referralClaimFailed => 'ते आमंत्रण वापरता आले नाही.';
}

class ApiConstants {
  // Base URLs
  static const String stagingBaseUrl =
      'https://landa-os-staging.onrender.com/api/users';
  static const String localBaseUrl = 'http://127.0.0.1:8000/api/users';
  static const String androidEmulatorBaseUrl = 'http://10.0.2.2:8000/api/users';

  // Default Base URL (Staging per flutter_api_guide.md)
  static String baseUrl = stagingBaseUrl;

  // Endpoint Paths
  static const String registerEndpoint = '/register/';
  static const String loginEndpoint = '/login/';
  static const String refreshTokenEndpoint = '/token/refresh/';
  static const String profileEndpoint = '/profile/';
  static const String verifyEndpoint = '/verify/';
  static const String verificationStatusEndpoint = '/verify/status/';
  static const String passwordResetRequestEndpoint = '/password/reset/request/';
  static const String passwordResetConfirmEndpoint = '/password/reset/confirm/';

  static const String propertiesEndpoint = '/properties/';
  static String propertyDetailEndpoint(String propertyId) =>
      '/properties/$propertyId/';
  static String propertyUnitsEndpoint(String propertyId) =>
      '/properties/$propertyId/units/';
  static String propertyUnitsBatchEndpoint(String propertyId) =>
      '/properties/$propertyId/units/batch/';
  static String assignTenantEndpoint(String unitId) => '/units/$unitId/assign/';
  static const String tenantAssignedUnitEndpoint = '/tenant/assigned-unit/';

  static const String agreementsEndpoint = '/agreements/';
  static String signAgreementEndpoint(String agreementId) =>
      '/agreements/$agreementId/sign/';

  static const String paymentsEndpoint = '/payments/';
  static String paymentReceiptEndpoint(String paymentId) =>
      '/payments/$paymentId/';
  static String verifyPaymentEndpoint(String paymentId) =>
      '/payments/$paymentId/verify/';
  static String releaseEscrowEndpoint(String paymentId) =>
      '/payments/$paymentId/release/';
  static String escrowStatusEndpoint(String paymentId) =>
      '/payments/$paymentId/escrow/';
  static String disputePaymentEndpoint(String paymentId) =>
      '/payments/$paymentId/dispute/';

  static const String notificationsEndpoint = '/notifications/';
  static String markNotificationReadEndpoint(String notificationId) =>
      '/notifications/$notificationId/read/';
}

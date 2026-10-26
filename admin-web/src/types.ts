export type AdminSection =
  | "overview"
  | "finance"
  | "bookings"
  | "listings"
  | "people"
  | "support";

export type BookingStatus = "Awaiting host" | "Paid" | "Checked out" | "Cancelled";
export type ReviewStatus = "Needs review" | "Live" | "Changes requested";
export type PersonStatus = "Verified" | "In review" | "Needs attention";
export type FinanceStatus = "In escrow" | "Ready to release" | "Refund review" | "Paid out" | "Resolved";
export type FinanceActionKind = "release_payout" | "refund" | "resolve_dispute" | "hold_escrow";

export interface FinanceAction {
  kind: FinanceActionKind;
  label: string;
  amount: string;
  confirmation: string;
}

export interface BookingRecord {
  id: string;
  reference: string;
  guest: string;
  host: string;
  listing: string;
  location: string;
  dates: string;
  amount: string;
  status: BookingStatus;
  supportFlag?: string;
}

export interface ListingRecord {
  id: string;
  title: string;
  host: string;
  location: string;
  nightlyPrice: string;
  status: ReviewStatus;
  submitted: string;
  description: string;
}

export interface PersonRecord {
  id: string;
  name: string;
  email: string;
  role: "Guest" | "Host";
  verification: PersonStatus;
  joined: string;
  stays: number;
}

export interface FinanceRecord {
  id: string;
  reference: string;
  booking: string;
  counterparty: string;
  kind: "Guest payment" | "Host payout" | "Refund" | "Caution fee";
  amount: string;
  status: FinanceStatus;
  date: string;
  actions: FinanceAction[];
}

export interface AuditRecord {
  id: string;
  reference: string;
  actor: string;
  action: string;
  amount: string;
  recordedAt: string;
  outcome: string;
}

export interface OverviewMetrics {
  grossVolume: string;
  activeStays: string;
  pendingReviews: string;
  financeQueue: string;
  volumeChange: string;
}

export interface FinanceSummary {
  heldInEscrow: string;
  readyForPayout: string;
  refundsThisMonth: string;
}

export interface AdminRepository {
  getOverview(): Promise<OverviewMetrics>;
  getBookings(): Promise<BookingRecord[]>;
  getListings(): Promise<ListingRecord[]>;
  getPeople(): Promise<PersonRecord[]>;
  getFinanceRecords(): Promise<FinanceRecord[]>;
  getFinanceSummary(): Promise<FinanceSummary>;
  getAuditRecords(): Promise<AuditRecord[]>;
  performFinanceAction(recordId: string, action: FinanceActionKind): Promise<void>;
  reviewListing(listingId: string, decision: "approve" | "request_changes"): Promise<void>;
  updateBooking(bookingId: string, decision: "resolve" | "escalate"): Promise<void>;
}

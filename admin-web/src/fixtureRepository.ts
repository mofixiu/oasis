import type {
  AdminRepository,
  AuditRecord,
  BookingRecord,
  FinanceActionKind,
  FinanceRecord,
  FinanceSummary,
  ListingRecord,
  OverviewMetrics,
  PersonRecord,
} from "./types";

const wait = () => new Promise<void>((resolve) => window.setTimeout(resolve, 120));

const bookingData: BookingRecord[] = [
  {
    id: "bk-1284",
    reference: "OS-1284",
    guest: "Amara Okafor",
    host: "Tunde Bakare",
    listing: "The Solace Apartment",
    location: "Lekki, Lagos",
    dates: "12–15 Dec 2026",
    amount: "₦540,000",
    status: "Paid",
  },
  {
    id: "bk-1279",
    reference: "OS-1279",
    guest: "Chika Eze",
    host: "Zainab Bello",
    listing: "Elysian Loft",
    location: "Victoria Island, Lagos",
    dates: "18–21 Dec 2026",
    amount: "₦750,000",
    status: "Awaiting host",
  },
  {
    id: "bk-1272",
    reference: "OS-1272",
    guest: "Kemi Adebayo",
    host: "Musa Ibrahim",
    listing: "Maison 14",
    location: "Ikoyi, Lagos",
    dates: "07–10 Dec 2026",
    amount: "₦630,000",
    status: "Paid",
    supportFlag: "Caution fee claim",
  },
  {
    id: "bk-1261",
    reference: "OS-1261",
    guest: "David James",
    host: "Bisi Adetola",
    listing: "The Horizon",
    location: "Oniru, Lagos",
    dates: "28 Nov–01 Dec 2026",
    amount: "₦660,000",
    status: "Checked out",
  },
];

const listingData: ListingRecord[] = [
  {
    id: "li-404",
    title: "The Palm House",
    host: "Tunde Bakare",
    location: "Lekki Phase 1, Lagos",
    nightlyPrice: "₦185,000 / night",
    status: "Needs review",
    submitted: "Today, 9:24 AM",
    description: "Two bedroom serviced apartment with a pool and 24-hour security.",
  },
  {
    id: "li-398",
    title: "The Elysian Loft",
    host: "Zainab Bello",
    location: "Victoria Island, Lagos",
    nightlyPrice: "₦250,000 / night",
    status: "Needs review",
    submitted: "Yesterday, 4:12 PM",
    description: "Bright city loft with a private terrace and water views.",
  },
  {
    id: "li-391",
    title: "Garden Suite",
    host: "Musa Ibrahim",
    location: "Ikoyi, Lagos",
    nightlyPrice: "₦160,000 / night",
    status: "Changes requested",
    submitted: "14 Oct 2026",
    description: "Quiet serviced studio near restaurants and the waterfront.",
  },
];

const peopleData: PersonRecord[] = [
  { id: "u-923", name: "Amara Okafor", email: "amara@example.test", role: "Guest", verification: "Verified", joined: "06 Oct 2026", stays: 3 },
  { id: "u-916", name: "Tunde Bakare", email: "tunde@example.test", role: "Host", verification: "Verified", joined: "28 Sep 2026", stays: 8 },
  { id: "u-910", name: "Chika Eze", email: "chika@example.test", role: "Guest", verification: "In review", joined: "15 Oct 2026", stays: 0 },
  { id: "u-902", name: "Zainab Bello", email: "zainab@example.test", role: "Host", verification: "Needs attention", joined: "11 Sep 2026", stays: 5 },
  { id: "u-899", name: "Kemi Adebayo", email: "kemi@example.test", role: "Guest", verification: "Verified", joined: "09 Sep 2026", stays: 2 },
];

const action = (
  kind: FinanceActionKind,
  label: string,
  amount: string,
  confirmation: string,
) => ({ kind, label, amount, confirmation });

const financeData: FinanceRecord[] = [
  {
    id: "fn-1284",
    reference: "TX-981284",
    booking: "OS-1284 · The Solace Apartment",
    counterparty: "Amara Okafor",
    kind: "Guest payment",
    amount: "₦540,000",
    status: "In escrow",
    date: "15 Oct 2026 · 10:24 AM",
    actions: [action("hold_escrow", "Review hold", "₦540,000", "Place this booking payment on a support hold?")],
  },
  {
    id: "fn-1272",
    reference: "TX-981272",
    booking: "OS-1272 · Maison 14",
    counterparty: "Kemi Adebayo",
    kind: "Caution fee",
    amount: "₦100,000",
    status: "Refund review",
    date: "15 Oct 2026 · 9:51 AM",
    actions: [action("refund", "Review refund", "₦100,000", "Submit the backend-authorized caution fee refund?")],
  },
  {
    id: "fn-1261",
    reference: "TX-981261",
    booking: "OS-1261 · The Horizon",
    counterparty: "Bisi Adetola",
    kind: "Host payout",
    amount: "₦594,000",
    status: "Ready to release",
    date: "14 Oct 2026 · 2:08 PM",
    actions: [action("release_payout", "Review payout", "₦594,000", "Release the payout amount authorized by the backend?")],
  },
  {
    id: "fn-1256",
    reference: "TX-981256",
    booking: "OS-1256 · Elysian Loft",
    counterparty: "Zainab Bello",
    kind: "Refund",
    amount: "₦75,000",
    status: "Resolved",
    date: "13 Oct 2026 · 11:36 AM",
    actions: [],
  },
];

export class FixtureAdminRepository implements AdminRepository {
  private bookings = [...bookingData];
  private listings = [...listingData];
  private people = [...peopleData];
  private finance = [...financeData];
  private audit: AuditRecord[] = [];

  async getOverview(): Promise<OverviewMetrics> {
    await wait();
    return {
      grossVolume: "₦18.4m",
      activeStays: "126",
      pendingReviews: `${this.listings.filter((item) => item.status === "Needs review").length}`,
      financeQueue: `${this.finance.filter((item) => item.actions.length > 0).length}`,
      volumeChange: "+12.8%",
    };
  }

  async getBookings(): Promise<BookingRecord[]> { await wait(); return [...this.bookings]; }
  async getListings(): Promise<ListingRecord[]> { await wait(); return [...this.listings]; }
  async getPeople(): Promise<PersonRecord[]> { await wait(); return [...this.people]; }
  async getFinanceRecords(): Promise<FinanceRecord[]> { await wait(); return [...this.finance]; }
  async getFinanceSummary(): Promise<FinanceSummary> {
    await wait();
    return {
      heldInEscrow: "₦8,240,000",
      readyForPayout: "₦1,845,000",
      refundsThisMonth: "₦325,000",
    };
  }
  async getAuditRecords(): Promise<AuditRecord[]> { await wait(); return [...this.audit]; }

  async performFinanceAction(recordId: string, kind: FinanceActionKind): Promise<void> {
    await wait();
    const record = this.finance.find((item) => item.id === recordId);
    if (!record || !record.actions.some((item) => item.kind === kind)) {
      throw new Error("That action is no longer available in this demo record.");
    }
    const authorizedAction = record.actions.find((item) => item.kind === kind)!;
    const nextStatus = kind === "release_payout"
      ? "Paid out"
      : kind === "refund"
        ? "Resolved"
        : kind === "hold_escrow"
          ? "In escrow"
          : "Resolved";
    this.finance = this.finance.map((item) => item.id === recordId
      ? { ...item, status: nextStatus, actions: [] }
      : item);
    this.audit = [{
      id: `audit-${Date.now()}-${record.id}`,
      reference: record.reference,
      actor: "M. Adebayo",
      action: authorizedAction.label,
      amount: authorizedAction.amount,
      recordedAt: new Intl.DateTimeFormat("en-NG", {
        dateStyle: "medium",
        timeStyle: "short",
      }).format(new Date()),
      outcome: "Recorded in the local demo. No funds moved.",
    }, ...this.audit];
  }

  async reviewListing(listingId: string, decision: "approve" | "request_changes"): Promise<void> {
    await wait();
    this.listings = this.listings.map((item) => item.id === listingId
      ? { ...item, status: decision === "approve" ? "Live" : "Changes requested" }
      : item);
  }

  async updateBooking(bookingId: string, decision: "resolve" | "escalate"): Promise<void> {
    await wait();
    if (!this.bookings.some((item) => item.id === bookingId)) {
      throw new Error("Booking was not found in this demo workspace.");
    }
    this.bookings = this.bookings.map((item) => item.id === bookingId
      ? { ...item, supportFlag: decision === "resolve" ? undefined : "Escalated for review" }
      : item);
  }
}

export const adminRepository = new FixtureAdminRepository();

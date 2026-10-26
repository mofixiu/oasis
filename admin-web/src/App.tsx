import { useEffect, useMemo, useState } from "react";
import {
  ArrowDownLeft,
  ArrowRight,
  ArrowUpRight,
  Bell,
  Building2,
  CalendarDays,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleHelp,
  ClipboardList,
  CreditCard,
  Download,
  FileCheck2,
  Filter,
  Home,
  Landmark,
  LayoutDashboard,
  LockKeyhole,
  LogOut,
  Menu,
  MoreHorizontal,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Users,
  Wallet,
  X,
  type LucideIcon,
} from "lucide-react";
import { adminRepository } from "./fixtureRepository";
import type {
  AdminSection,
  AuditRecord,
  BookingRecord,
  FinanceAction,
  FinanceRecord,
  FinanceSummary,
  ListingRecord,
  OverviewMetrics,
  PersonRecord,
} from "./types";

type LoadedData = {
  overview: OverviewMetrics;
  bookings: BookingRecord[];
  listings: ListingRecord[];
  people: PersonRecord[];
  finance: FinanceRecord[];
  audit: AuditRecord[];
  financeSummary: FinanceSummary;
};

type PendingDialog = {
  title: string;
  body: string;
  amount?: string;
  actionLabel: string;
  onConfirm: () => Promise<void>;
};

const navigation: { id: AdminSection; label: string; icon: LucideIcon }[] = [
  { id: "overview", label: "Overview", icon: LayoutDashboard },
  { id: "bookings", label: "Bookings", icon: CalendarDays },
  { id: "listings", label: "Listing review", icon: Building2 },
  { id: "people", label: "People & KYC", icon: Users },
  { id: "finance", label: "Finance", icon: Wallet },
  { id: "support", label: "Support cases", icon: CircleHelp },
];

const sectionTitles: Record<AdminSection, { title: string; subtitle: string }> = {
  overview: { title: "Good morning, Mofiyin", subtitle: "Here is what is happening across Oasis today." },
  bookings: { title: "Bookings", subtitle: "Follow each stay from request to check-out." },
  listings: { title: "Listing review", subtitle: "Help guests find clear, trustworthy places to stay." },
  people: { title: "People & verification", subtitle: "Look up accounts and their verification standing." },
  finance: { title: "Finance", subtitle: "Review escrow, guest refunds and host payouts." },
  support: { title: "Support cases", subtitle: "Keep guest and host concerns moving toward resolution." },
};

export default function App() {
  const [signedIn, setSignedIn] = useState(false);
  const [section, setSection] = useState<AdminSection>("overview");
  const [data, setData] = useState<LoadedData | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<PendingDialog | null>(null);
  const [dialogBusy, setDialogBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [search, setSearch] = useState("");

  const reload = async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const [overview, bookings, listings, people, finance, audit, financeSummary] = await Promise.all([
        adminRepository.getOverview(),
        adminRepository.getBookings(),
        adminRepository.getListings(),
        adminRepository.getPeople(),
        adminRepository.getFinanceRecords(),
        adminRepository.getAuditRecords(),
        adminRepository.getFinanceSummary(),
      ]);
      setData({ overview, bookings, listings, people, finance, audit, financeSummary });
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : "Could not load the workspace.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (signedIn) void reload();
  }, [signedIn]);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 3600);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const page = useMemo(() => sectionTitles[section], [section]);

  if (!signedIn) {
    return <LoginScreen onDemo={() => setSignedIn(true)} />;
  }

  const runDialogAction = async () => {
    if (!dialog || dialogBusy) return;
    setDialogBusy(true);
    try {
      await dialog.onConfirm();
      await reload();
      setToast("Demo action recorded locally. No money moved.");
      setDialog(null);
    } catch (error) {
      setToast(error instanceof Error ? error.message : "Action could not be completed.");
    } finally {
      setDialogBusy(false);
    }
  };

  const openFinanceAction = (record: FinanceRecord, action: FinanceAction) => {
    setDialog({
      title: action.label,
      body: action.confirmation,
      amount: action.amount,
      actionLabel: "Confirm in demo",
      onConfirm: () => adminRepository.performFinanceAction(record.id, action.kind),
    });
  };

  const openListingReview = (listing: ListingRecord, decision: "approve" | "request_changes") => {
    const approve = decision === "approve";
    setDialog({
      title: approve ? "Approve this listing?" : "Request listing changes?",
      body: approve
        ? `${listing.title} will be marked ready to appear in Stay discovery.`
        : `${listing.title} will be returned to ${listing.host} for updates.`,
      actionLabel: approve ? "Approve in demo" : "Request changes",
      onConfirm: () => adminRepository.reviewListing(listing.id, decision),
    });
  };

  const openBookingReview = (booking: BookingRecord, decision: "resolve" | "escalate") => {
    const resolve = decision === "resolve";
    setDialog({
      title: resolve ? "Resolve this support case?" : "Escalate this case?",
      body: resolve
        ? `Mark the case for ${booking.reference} as resolved in this local demo.`
        : `Keep ${booking.reference} open and flag it for a senior review.`,
      actionLabel: resolve ? "Resolve in demo" : "Escalate case",
      onConfirm: () => adminRepository.updateBooking(booking.id, decision),
    });
  };

  const setActiveSection = (next: AdminSection) => {
    setSection(next);
    setSearch("");
    setMobileNavOpen(false);
  };

  return (
    <div className="admin-shell">
      <aside className={`sidebar ${mobileNavOpen ? "sidebar-open" : ""}`}>
        <div className="brand-lockup">
          <img className="brand-symbol" src="/oasis-app-icon.png" alt="" />
          <img className="brand-wordmark" src="/oasis-wordmark.png" alt="Oasis" />
          <span className="brand-caption">OPERATIONS</span>
        </div>
        <div className="sidebar-label">WORKSPACE</div>
        <nav className="side-nav" aria-label="Admin sections">
          {navigation.map(({ id, label, icon: Icon }) => (
            <button
              className={`nav-item ${section === id ? "nav-item-active" : ""}`}
              key={id}
              onClick={() => setActiveSection(id)}
            >
              <Icon size={18} strokeWidth={1.9} />
              <span>{label}</span>
              {id === "listings" && data && data.overview.pendingReviews !== "0" && (
                <span className="nav-count">{data.overview.pendingReviews}</span>
              )}
              {id === "finance" && data && data.overview.financeQueue !== "0" && (
                <span className="nav-count nav-count-warm">{data.overview.financeQueue}</span>
              )}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="help-card">
            <div className="help-icon"><ShieldCheck size={17} /></div>
            <strong>Trust comes first.</strong>
            <span>Every money decision is recorded and reviewable.</span>
          </div>
          <button className="staff-profile" onClick={() => setSignedIn(false)}>
            <span className="staff-avatar">MA</span>
            <span className="staff-copy"><b>M. Adebayo</b><small>Operations staff</small></span>
            <LogOut size={16} className="staff-logout" />
          </button>
        </div>
      </aside>

      <div className="workspace">
        <header className="topbar">
          <button className="mobile-menu icon-button" aria-label="Open navigation" onClick={() => setMobileNavOpen((open) => !open)}>
            {mobileNavOpen ? <X size={20} /> : <Menu size={20} />}
          </button>
          <div className="breadcrumbs"><span>Operations</span><ChevronRight size={15} /><b>{page.title}</b></div>
          <div className="topbar-actions">
            <span className="demo-pill"><span /> DEMO WORKSPACE</span>
            <button className="icon-button notification-button" aria-label="Notifications"><Bell size={18} /><i /></button>
            <button className="top-avatar" aria-label="Staff profile">MA</button>
          </div>
        </header>

        <main className="page-content">
          <div className="page-heading">
            <div>
              <div className="eyebrow">OASIS · STAFF CONSOLE</div>
              <h1>{page.title}</h1>
              <p>{page.subtitle}</p>
            </div>
            <div className="heading-tools">
              <label className="search-box">
                <Search size={17} />
                <input
                  aria-label="Search this page"
                  placeholder={section === "people" ? "Search name or email" : "Search reference or guest"}
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
                <kbd>⌘ K</kbd>
              </label>
              <button className="filter-button" onClick={() => setToast("Filters are ready for the connected admin API.")}><SlidersHorizontal size={16} /><span>Filters</span></button>
            </div>
          </div>

          <div className="demo-banner">
            <span className="demo-banner-icon"><Sparkles size={16} /></span>
            <span><b>Local demo data.</b> Records and actions on this page are examples. No guest data or funds are changed.</span>
            <button onClick={() => void reload()} aria-label="Refresh demo data"><ArrowRight size={16} /></button>
          </div>

          {loadError ? (
            <div className="error-panel"><CircleHelp size={20} /><div><b>We could not open this workspace.</b><span>{loadError}</span></div><button className="button button-light" onClick={() => void reload()}>Try again</button></div>
          ) : loading && !data ? (
            <LoadingPanel />
          ) : data ? (
            <SectionView
              section={section}
              data={data}
              search={search}
              onSection={setActiveSection}
              onFinanceAction={openFinanceAction}
              onListingReview={openListingReview}
              onBookingReview={openBookingReview}
            />
          ) : null}

          <footer className="page-footer"><span>Oasis Operations</span><span>Short stays · Lagos, Nigeria</span><span><LockKeyhole size={13} /> Staff workspace</span></footer>
        </main>
      </div>

      {dialog && (
        <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !dialogBusy) setDialog(null); }}>
          <section className="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title">
            <button className="modal-close icon-button" aria-label="Close confirmation" onClick={() => setDialog(null)}><X size={18} /></button>
            <div className="modal-mark"><ShieldCheck size={21} /></div>
            <div className="eyebrow">DEMO ACTION</div>
            <h2 id="dialog-title">{dialog.title}</h2>
            <p>{dialog.body}</p>
            {dialog.amount && <div className="modal-amount"><span>Backend-authorized amount</span><b>{dialog.amount}</b></div>}
            <div className="modal-note"><LockKeyhole size={15} /><span>In live mode, the backend determines availability and amount. This demo only updates local sample data.</span></div>
            <div className="modal-actions">
              <button className="button button-light" disabled={dialogBusy} onClick={() => setDialog(null)}>Cancel</button>
              <button className="button button-primary" disabled={dialogBusy} onClick={() => void runDialogAction()}>{dialogBusy ? "Saving…" : dialog.actionLabel}</button>
            </div>
          </section>
        </div>
      )}
      {toast && <div className="toast"><CheckCircle2 size={17} />{toast}<button aria-label="Dismiss" onClick={() => setToast(null)}><X size={15} /></button></div>}
      {mobileNavOpen && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMobileNavOpen(false)} />}
    </div>
  );
}

function LoginScreen({ onDemo }: { onDemo: () => void }) {
  const isDevelopment = import.meta.env.DEV;
  return (
    <main className="login-page">
      <div className="login-brand"><img className="brand-wordmark" src="/oasis-wordmark.png" alt="Oasis" /></div>
      <section className="login-card">
        <div className="login-kicker"><LockKeyhole size={15} /> STAFF WORKSPACE</div>
        <h1>Welcome back.</h1>
        <p>Sign in to review stays, support and settlement activity.</p>
        {isDevelopment ? (
          <>
            <div className="local-demo-note"><Sparkles size={17} /><span><b>Local preview</b><small>This demo uses sample records only.</small></span></div>
            <button className="button button-primary login-submit" onClick={onDemo}>Enter demo workspace <ArrowRight size={17} /></button>
          </>
        ) : (
          <>
            <label className="field-label">Work email<input type="email" placeholder="you@oasis.ng" disabled /></label>
            <label className="field-label">Password<input type="password" placeholder="••••••••••••" disabled /></label>
            <button className="button button-primary login-submit" disabled>Staff sign-in is not connected yet</button>
            <small className="auth-placeholder">Production access requires the backend staff-auth integration.</small>
          </>
        )}
      </section>
      <div className="login-foot"><ShieldCheck size={14} /> Every decision protects a real stay.</div>
    </main>
  );
}

function SectionView({
  section,
  data,
  search,
  onSection,
  onFinanceAction,
  onListingReview,
  onBookingReview,
}: {
  section: AdminSection;
  data: LoadedData;
  search: string;
  onSection: (section: AdminSection) => void;
  onFinanceAction: (record: FinanceRecord, action: FinanceAction) => void;
  onListingReview: (listing: ListingRecord, decision: "approve" | "request_changes") => void;
  onBookingReview: (booking: BookingRecord, decision: "resolve" | "escalate") => void;
}) {
  if (section === "overview") return <OverviewView data={data} onSection={onSection} onFinanceAction={onFinanceAction} />;
  if (section === "finance") return <FinanceView records={data.finance} summary={data.financeSummary} audit={data.audit} search={search} onFinanceAction={onFinanceAction} />;
  if (section === "bookings") return <BookingsView bookings={data.bookings} search={search} onBookingReview={onBookingReview} />;
  if (section === "support") return <SupportView bookings={data.bookings} onBookingReview={onBookingReview} />;
  if (section === "listings") return <ListingsView listings={data.listings} search={search} onListingReview={onListingReview} />;
  return <PeopleView people={data.people} search={search} />;
}

function OverviewView({ data, onSection, onFinanceAction }: {
  data: LoadedData;
  onSection: (section: AdminSection) => void;
  onFinanceAction: (record: FinanceRecord, action: FinanceAction) => void;
}) {
  const metrics = [
    { label: "Gross booking volume", value: data.overview.grossVolume, icon: Wallet, change: data.overview.volumeChange, tone: "green" },
    { label: "Active stays", value: data.overview.activeStays, icon: CalendarDays, change: "Across current bookings", tone: "sand" },
    { label: "Listings to review", value: data.overview.pendingReviews, icon: Building2, change: "Needs staff attention", tone: "rose" },
    { label: "Finance queue", value: data.overview.financeQueue, icon: Landmark, change: "Backend-authorized actions", tone: "slate" },
  ];
  const pendingFinance = data.finance.filter((record) => record.actions.length > 0).slice(0, 3);
  const recentBookings = data.bookings.slice(0, 4);
  return (
    <>
      <div className="metric-grid">
        {metrics.map(({ label, value, icon: Icon, change, tone }) => (
          <article className="metric-card" key={label}>
            <div className={`metric-icon ${tone}`}><Icon size={19} /></div>
            <span className="metric-label">{label}</span>
            <div className="metric-value-row"><strong>{value}</strong>{tone === "green" && <span className="trend"><ArrowUpRight size={14} />{change}</span>}</div>
            {tone !== "green" && <span className="metric-note">{change}</span>}
            {tone === "green" && <span className="metric-note">vs. previous 30 days</span>}
          </article>
        ))}
      </div>

      <div className="overview-grid">
        <section className="panel volume-panel">
          <div className="panel-heading"><div><span className="eyebrow">MONEY IN MOTION</span><h2>Booking volume</h2></div><button className="period-select">Last 30 days <ChevronDown size={14} /></button></div>
          <div className="chart-summary"><strong>₦18,420,000</strong><span className="positive"><ArrowUpRight size={14} /> 12.8%</span><small>compared with last month</small></div>
          <div className="chart" role="img" aria-label="Illustrative booking volume over the last 30 days">
            <div className="chart-y"><span>₦8m</span><span>₦6m</span><span>₦4m</span><span>₦2m</span><span>₦0</span></div>
            <div className="chart-area"><div className="chart-gridlines"><i /><i /><i /><i /><i /></div><svg viewBox="0 0 700 190" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="volumeFill" x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="#b65f3c" stopOpacity=".22"/><stop offset="100%" stopColor="#b65f3c" stopOpacity="0"/></linearGradient></defs><path className="chart-fill" d="M0,147 C34,141 37,117 74,126 S117,150 145,113 S188,119 217,97 S262,109 289,86 S323,101 358,80 S401,94 432,63 S470,86 505,67 S544,88 575,44 S620,66 649,33 S679,41 700,18 L700,190 L0,190 Z"/><path className="chart-line" d="M0,147 C34,141 37,117 74,126 S117,150 145,113 S188,119 217,97 S262,109 289,86 S323,101 358,80 S401,94 432,63 S470,86 505,67 S544,88 575,44 S620,66 649,33 S679,41 700,18"/></svg><div className="chart-x"><span>16 Sep</span><span>23 Sep</span><span>30 Sep</span><span>07 Oct</span><span>15 Oct</span></div></div>
          </div>
        </section>
        <section className="panel queue-panel">
          <div className="panel-heading"><div><span className="eyebrow">NEEDS A LOOK</span><h2>Finance queue</h2></div><button className="text-button" onClick={() => onSection("finance")}>View all <ArrowRight size={15} /></button></div>
          {pendingFinance.length ? pendingFinance.map((record) => <FinanceQueueRow key={record.id} record={record} onAction={onFinanceAction} />) : <EmptyNotice title="You are all caught up" message="New authorized finance actions will appear here." />}
          <div className="queue-foot"><CheckCircle2 size={14} /> Action amounts come from the backend.</div>
        </section>
      </div>

      <section className="panel table-panel">
        <div className="panel-heading"><div><span className="eyebrow">LATEST ACTIVITY</span><h2>Recent bookings</h2></div><button className="text-button" onClick={() => onSection("bookings")}>All bookings <ArrowRight size={15} /></button></div>
        <BookingTable bookings={recentBookings} compact />
      </section>
    </>
  );
}

function FinanceView({ records, summary, audit, search, onFinanceAction }: {
  records: FinanceRecord[];
  summary: FinanceSummary;
  audit: AuditRecord[];
  search: string;
  onFinanceAction: (record: FinanceRecord, action: FinanceAction) => void;
}) {
  const [filter, setFilter] = useState("All activity");
  const filtered = records.filter((record) => {
    const matchesSearch = `${record.reference} ${record.booking} ${record.counterparty}`.toLowerCase().includes(search.toLowerCase());
    const matchesFilter = filter === "All activity" || record.status === filter;
    return matchesSearch && matchesFilter;
  });
  const queueCount = records.filter((record) => record.actions.length > 0).length;
  return (
    <>
      <div className="finance-summary-grid">
        <SummaryCard label="Held in escrow" value={summary.heldInEscrow} note="Active guest payments" icon={LockKeyhole} />
        <SummaryCard label="Ready for payout" value={summary.readyForPayout} note={`${queueCount} actions available in demo`} icon={ArrowUpRight} />
        <SummaryCard label="Refunds this month" value={summary.refundsThisMonth} note="Backend-authorized totals" icon={ArrowDownLeft} />
      </div>
      <section className="panel table-panel">
        <div className="panel-heading finance-heading"><div><span className="eyebrow">PAYMENTS & SETTLEMENTS</span><h2>Finance ledger</h2></div><button className="button button-light export-button" onClick={() => window.print()}><Download size={16} /> Export view</button></div>
        <div className="table-toolbar"><div className="filter-tabs">{["All activity", "In escrow", "Ready to release", "Refund review", "Paid out"].map((item) => <button className={filter === item ? "filter-tab selected" : "filter-tab"} key={item} onClick={() => setFilter(item)}>{item}</button>)}</div><button className="subtle-filter"><Filter size={15} /> More filters</button></div>
        {filtered.length ? <FinanceTable records={filtered} onFinanceAction={onFinanceAction} /> : <EmptyNotice title="No finance records match" message="Change your search or select another status." />}
      </section>
      <div className="finance-rule"><ShieldCheck size={18} /><span><b>Backend decides what can move.</b> This interface displays authorized actions and returned amounts. It never calculates refunds or releases money on its own.</span></div>
      <section className="panel audit-panel">
        <div className="panel-heading"><div><span className="eyebrow">AUDIT TRAIL</span><h2>Recent finance decisions</h2></div><span className="results-count">{audit.length} records</span></div>
        {audit.length ? <div className="audit-list">{audit.map((entry) => (
          <article className="audit-entry" key={entry.id}>
            <div className="audit-mark"><Check size={16} /></div>
            <div className="audit-copy"><b>{entry.action} · {entry.reference}</b><span>{entry.actor} · {entry.recordedAt}</span><small>{entry.outcome}</small></div>
            <strong>{entry.amount}</strong>
          </article>
        ))}</div> : <EmptyNotice title="No demo finance decisions yet" message="Confirmed actions will appear here with the staff member, authorized amount and outcome." icon={ShieldCheck} />}
      </section>
    </>
  );
}

function BookingsView({ bookings, search, onBookingReview }: {
  bookings: BookingRecord[];
  search: string;
  onBookingReview: (booking: BookingRecord, decision: "resolve" | "escalate") => void;
}) {
  const visible = bookings.filter((booking) => `${booking.reference} ${booking.guest} ${booking.host} ${booking.listing}`.toLowerCase().includes(search.toLowerCase()));
  return (
    <section className="panel table-panel">
      <div className="panel-heading"><div><span className="eyebrow">SHORT STAYS</span><h2>Booking activity</h2></div><span className="results-count">{visible.length} records</span></div>
      <BookingTable bookings={visible} onReview={onBookingReview} />
    </section>
  );
}

function SupportView({ bookings, onBookingReview }: {
  bookings: BookingRecord[];
  onBookingReview: (booking: BookingRecord, decision: "resolve" | "escalate") => void;
}) {
  const flagged = bookings.filter((booking) => booking.supportFlag);
  return (
    <section className="panel table-panel">
      <div className="panel-heading"><div><span className="eyebrow">GUEST & HOST CARE</span><h2>Open support cases</h2></div><span className="results-count">{flagged.length} open</span></div>
      {flagged.length ? <BookingTable bookings={flagged} onReview={onBookingReview} support /> : <EmptyNotice title="No open cases" message="New guest and host concerns will appear here." icon={CheckCircle2} />}
    </section>
  );
}

function ListingsView({ listings, search, onListingReview }: {
  listings: ListingRecord[];
  search: string;
  onListingReview: (listing: ListingRecord, decision: "approve" | "request_changes") => void;
}) {
  const visible = listings.filter((listing) => `${listing.title} ${listing.host} ${listing.location}`.toLowerCase().includes(search.toLowerCase()));
  return (
    <>
      <div className="listing-review-note"><FileCheck2 size={18} /><span>Review the information and media in the backend before approving a place for guest discovery.</span><span className="review-queue-count">{visible.filter((item) => item.status === "Needs review").length} awaiting review</span></div>
      {visible.length ? <div className="listing-grid">{visible.map((listing) => <ListingCard listing={listing} key={listing.id} onReview={onListingReview} />)}</div> : <section className="panel table-panel"><EmptyNotice title="No listings found" message="Try a different name or location." /></section>}
    </>
  );
}

function PeopleView({ people, search }: { people: PersonRecord[]; search: string }) {
  const visible = people.filter((person) => `${person.name} ${person.email} ${person.id}`.toLowerCase().includes(search.toLowerCase()));
  return (
    <section className="panel table-panel">
      <div className="panel-heading"><div><span className="eyebrow">ACCOUNT DIRECTORY</span><h2>People & verification</h2></div><span className="privacy-chip"><ShieldCheck size={14} /> Sensitive identity details stay protected</span></div>
      {visible.length ? <PeopleTable people={visible} /> : <EmptyNotice title="No people found" message="Try another name, email or account reference." />}
      <div className="privacy-note"><LockKeyhole size={15} /> Only the verification status is shown here. Private documents and identity data require authorized backend access.</div>
    </section>
  );
}

function BookingTable({ bookings, compact = false, support = false, onReview }: {
  bookings: BookingRecord[];
  compact?: boolean;
  support?: boolean;
  onReview?: (booking: BookingRecord, decision: "resolve" | "escalate") => void;
}) {
  if (!bookings.length) return <EmptyNotice title="No bookings found" message="New stays will appear as guests and hosts use Oasis." />;
  return (
    <div className="table-scroll"><table><thead><tr><th>BOOKING</th><th>GUEST & HOST</th><th>DATES</th><th>AMOUNT</th><th>STATUS</th>{!compact && <th />}</tr></thead><tbody>
      {bookings.map((booking) => <tr key={booking.id}>
        <td><b>{booking.reference}</b><small>{booking.listing}<br />{booking.location}</small></td>
        <td><span className="person-pair"><span className="mini-avatar">{initials(booking.guest)}</span><span>{booking.guest}<small>Host: {booking.host}</small></span></span></td>
        <td>{booking.dates}</td>
        <td className="amount-cell">{booking.amount}</td>
        <td><StatusBadge label={support ? booking.supportFlag ?? "Open case" : booking.status} /></td>
        {!compact && <td className="action-cell">{onReview && (support || booking.supportFlag) ? <button className="row-action" onClick={() => onReview(booking, "resolve")}>Review case <ArrowRight size={14} /></button> : <button className="icon-button row-more" aria-label={`More actions for ${booking.reference}`}><MoreHorizontal size={18} /></button>}</td>}
      </tr>)}
    </tbody></table></div>
  );
}

function FinanceTable({ records, onFinanceAction }: {
  records: FinanceRecord[];
  onFinanceAction: (record: FinanceRecord, action: FinanceAction) => void;
}) {
  return <div className="table-scroll"><table><thead><tr><th>REFERENCE</th><th>TYPE</th><th>COUNTERPARTY</th><th>AMOUNT</th><th>STATUS</th><th>DATE</th><th /></tr></thead><tbody>
    {records.map((record) => <tr key={record.id}>
      <td><b>{record.reference}</b><small>{record.booking}</small></td>
      <td><span className="type-cell">{financeIcon(record.kind)}{record.kind}</span></td>
      <td>{record.counterparty}</td>
      <td className="amount-cell">{record.amount}</td>
      <td><StatusBadge label={record.status} /></td>
      <td className="date-cell">{record.date}</td>
      <td className="action-cell">{record.actions[0] ? <button className="row-action" onClick={() => onFinanceAction(record, record.actions[0])}>{record.actions[0].label}<ArrowRight size={14} /></button> : <span className="muted-dash">—</span>}</td>
    </tr>)}
  </tbody></table></div>;
}

function PeopleTable({ people }: { people: PersonRecord[] }) {
  const [selected, setSelected] = useState<PersonRecord | null>(null);
  return <>
    <div className="table-scroll"><table><thead><tr><th>PERSON</th><th>ROLE</th><th>VERIFICATION</th><th>JOINED</th><th>STAYS</th><th /></tr></thead><tbody>
      {people.map((person) => <tr key={person.id}>
        <td><span className="person-pair"><span className="mini-avatar person-avatar">{initials(person.name)}</span><span><b>{person.name}</b><small>{person.email}</small></span></span></td>
        <td>{person.role}</td>
        <td><StatusBadge label={person.verification} /></td>
        <td>{person.joined}</td>
        <td>{person.stays}</td>
        <td className="action-cell"><button className="row-action" onClick={() => setSelected(person)}>View profile <ArrowRight size={14} /></button></td>
      </tr>)}
    </tbody></table></div>
    {selected && <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}><section className="confirm-modal person-modal" role="dialog" aria-modal="true"><button className="modal-close icon-button" aria-label="Close profile" onClick={() => setSelected(null)}><X size={18} /></button><div className="person-modal-avatar">{initials(selected.name)}</div><div className="eyebrow">ACCOUNT LOOKUP · {selected.id}</div><h2>{selected.name}</h2><p>{selected.email}</p><div className="person-facts"><span>Role<b>{selected.role}</b></span><span>Verification<b>{selected.verification}</b></span><span>Stays<b>{selected.stays}</b></span><span>Joined<b>{selected.joined}</b></span></div><div className="modal-note"><LockKeyhole size={15} /><span>No raw identity numbers or private documents are exposed in this demo view.</span></div><button className="button button-light modal-full" onClick={() => setSelected(null)}>Close</button></section></div>}
  </>;
}

function ListingCard({ listing, onReview }: {
  listing: ListingRecord;
  onReview: (listing: ListingRecord, decision: "approve" | "request_changes") => void;
}) {
  const canReview = listing.status === "Needs review";
  return <article className="listing-card">
    <div className="listing-photo"><div className="photo-arch"><Home size={29} /></div><span className="photo-dots"><i /><i /><i /></span><span className="listing-price">{listing.nightlyPrice}</span></div>
    <div className="listing-card-body"><div className="listing-card-top"><div><span className="eyebrow">{listing.location}</span><h3>{listing.title}</h3></div><StatusBadge label={listing.status} /></div><p>{listing.description}</p><div className="listing-host"><span className="mini-avatar">{initials(listing.host)}</span><span>Hosted by <b>{listing.host}</b></span><span className="listing-time">{listing.submitted}</span></div>
    {canReview ? <div className="listing-actions"><button className="button button-light" onClick={() => onReview(listing, "request_changes")}>Request changes</button><button className="button button-primary" onClick={() => onReview(listing, "approve")}><Check size={15} /> Approve listing</button></div> : <div className="listing-reviewed"><CheckCircle2 size={15} /> {listing.status === "Live" ? "Approved for discovery" : "Returned to host"}</div>}
    </div>
  </article>;
}

function FinanceQueueRow({ record, onAction }: {
  record: FinanceRecord;
  onAction: (record: FinanceRecord, action: FinanceAction) => void;
}) {
  const action = record.actions[0];
  return <div className="queue-row"><span className="queue-mark">{financeIcon(record.kind)}</span><span className="queue-copy"><b>{record.kind}</b><small>{record.reference} · {record.counterparty}</small></span><b className="queue-amount">{action?.amount ?? record.amount}</b>{action && <button className="queue-open" aria-label={`Review ${record.reference}`} onClick={() => onAction(record, action)}><ChevronRight size={17} /></button>}</div>;
}

function SummaryCard({ label, value, note, icon: Icon }: { label: string; value: string; note: string; icon: LucideIcon }) {
  return <article className="summary-card"><div className="summary-icon"><Icon size={18} /></div><span>{label}</span><strong>{value}</strong><small>{note}</small></article>;
}

function StatusBadge({ label }: { label: string }) {
  const lower = label.toLowerCase();
  const tone = lower.includes("paid") || lower.includes("verified") || lower.includes("live") || lower.includes("resolved") || lower.includes("checked out")
    ? "status-green"
    : lower.includes("review") || lower.includes("escrow") || lower.includes("awaiting") || lower.includes("open")
      ? "status-sand"
      : lower.includes("attention") || lower.includes("cancel") || lower.includes("changes") || lower.includes("refund")
        ? "status-rose"
        : "status-slate";
  return <span className={`status-badge ${tone}`}><i />{label}</span>;
}

function EmptyNotice({ title, message, icon: Icon = ClipboardList }: { title: string; message: string; icon?: LucideIcon }) {
  return <div className="empty-notice"><div className="empty-art"><span /><Icon size={25} /></div><b>{title}</b><p>{message}</p></div>;
}

function LoadingPanel() {
  return <div className="loading-grid" aria-label="Loading workspace"><div className="loading-card"/><div className="loading-card"/><div className="loading-card"/><div className="loading-card"/><div className="loading-wide"/><div className="loading-wide"/></div>;
}

function financeIcon(kind: FinanceRecord["kind"]) {
  if (kind === "Host payout") return <ArrowUpRight size={16} />;
  if (kind === "Refund") return <ArrowDownLeft size={16} />;
  if (kind === "Caution fee") return <ShieldCheck size={16} />;
  return <CreditCard size={16} />;
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
}

import { useEffect, useState } from "react";
import { Link, Route, Routes, useLocation } from "react-router-dom";
import { faqs, howItWorks, nav, packages, plans, serviceAreas, whyZylo } from "./data";

function ScrollToHash() {
  const { pathname, hash } = useLocation();
  useEffect(() => {
    if (pathname !== "/") return;
    if (!hash) {
      window.scrollTo({ top: 0, behavior: "smooth" });
      return;
    }
    const id = hash.replace("#", "");
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [pathname, hash]);
  return null;
}

function Header() {
  const [open, setOpen] = useState(false);
  return (
    <header className="site-header">
      <div className="shell nav-row">
        <Link className="brand" to="/" onClick={() => setOpen(false)}>
          ZYLO<span>.</span>
        </Link>
        <nav className="nav-links" aria-label="Primary">
          {nav.map((item) => (
            <a key={item.href} href={item.href}>
              {item.label}
            </a>
          ))}
        </nav>
        <div className="nav-cta">
          <a className="btn btn-dark" href="#contact">
            Get the app
          </a>
          <button
            type="button"
            className="menu-btn"
            aria-expanded={open}
            aria-controls="mobile-nav"
            onClick={() => setOpen((v) => !v)}
          >
            Menu
          </button>
        </div>
      </div>
      <div id="mobile-nav" className={`shell mobile-nav${open ? " open" : ""}`}>
        {nav.map((item) => (
          <a key={item.href} href={item.href} onClick={() => setOpen(false)}>
            {item.label}
          </a>
        ))}
      </div>
    </header>
  );
}

function Footer() {
  return (
    <footer className="site-footer">
      <div className="shell footer-grid">
        <div>
          <div className="footer-brand">ZYLO</div>
          <p>
            Doorstep car washing and detailing in Hyderabad, Telangana. Your car
            deserves a fresh start — without leaving home.
          </p>
        </div>
        <div>
          <h3>Explore</h3>
          <p>
            <a href="/#services">Services</a>
            <br />
            <a href="/#packages">Packages</a>
            <br />
            <a href="/#plans">Subscriptions</a>
            <br />
            <a href="/#faq">FAQs</a>
          </p>
        </div>
        <div>
          <h3>Legal & contact</h3>
          <p>
            <Link to="/privacy">Privacy Policy</Link>
            <br />
            <Link to="/terms">Terms and Conditions</Link>
            <br />
            <a href="mailto:support@zylo.app">support@zylo.app</a>
          </p>
        </div>
      </div>
      <div className="shell footer-meta">
        © {new Date().getFullYear()} ZYLO · Hyderabad, India ·{" "}
        <a href="https://zyloo.co.in/">zyloo.co.in</a>
      </div>
    </footer>
  );
}

function HomePage() {
  return (
    <>
      <section className="hero" aria-label="ZYLO hero">
        <div className="hero-media">
          <img
            src="/hero-car.jpg"
            alt="Clean car ready after a professional wash"
            width={1600}
            height={900}
          />
        </div>
        <div className="shell hero-content">
          <p className="eyebrow" style={{ color: "var(--accent-soft)" }}>
            Doorstep car wash · Hyderabad
          </p>
          <h1>Your Car Deserves a Fresh Start.</h1>
          <p>
            ZYLO brings professional car washing and detailing to your parking
            spot — foam, finish, and care at your doorstep across Hyderabad.
          </p>
          <div className="hero-actions">
            <a className="btn btn-primary" href="#contact">
              Book a Wash
            </a>
            <a className="btn btn-secondary" href="#services">
              Explore Services
            </a>
          </div>
        </div>
      </section>

      <section className="section" id="about">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">About ZYLO</span>
            <h2>Premium shine, without the trip to the workshop.</h2>
            <p>
              ZYLO is a doorstep car washing and detailing service built for
              busy drivers in Hyderabad. We come to your apartment, villa, or
              office parking so your car gets a clean start where it already is.
            </p>
          </div>
          <div className="grid-2">
            <div className="panel">
              <h3>What we do</h3>
              <p>
                Exterior washes, interior cleaning, full-service packages, and
                deeper detailing — scheduled around your day and finished by
                trained washing experts.
              </p>
            </div>
            <div className="panel">
              <h3>How you book</h3>
              <p>
                Use the ZYLO customer app to add your vehicle, share access
                notes, choose a package, and pay securely. A web booking portal
                is reserved for a future release at /app.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="services">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">Services</span>
            <h2>Care that meets your car where it parks.</h2>
            <p>
              From a quick exterior reset to a thorough deep clean, every visit
              is designed for doorstep convenience in Hyderabad.
            </p>
          </div>
          <div className="grid-4">
            {whyZylo.map((item) => (
              <article className="panel" key={item.title}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section" id="packages">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">Car wash packages</span>
            <h2>Popular packages for every level of care.</h2>
            <p>
              Starting prices below reflect hatchback rates in the ZYLO platform
              catalog. Exact totals depend on vehicle size and add-ons in the
              app.
            </p>
          </div>
          <div className="grid-2">
            {packages.map((pkg) => (
              <article className="panel" key={pkg.id}>
                <h3>{pkg.name}</h3>
                <p>{pkg.blurb}</p>
                <div className="price">
                  From ₹{pkg.fromInr} <span>· hatchback</span>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section" id="how">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">How it works</span>
            <h2>Four steps from booking to a fresh finish.</h2>
          </div>
          <div className="steps">
            {howItWorks.map((item) => (
              <article className="step" key={item.step}>
                <div className="step-num" aria-hidden="true">
                  {item.step}
                </div>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section" id="plans">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">Subscription plans</span>
            <h2>Keep the shine on a monthly rhythm.</h2>
            <p>
              Hatchback starting prices from the ZYLO platform catalog. Confirm
              vehicle size and billing details in the customer app at checkout.
            </p>
          </div>
          <div className="grid-3">
            {plans.map((plan) => (
              <article className="panel" key={plan.id}>
                <h3>
                  {plan.name}
                  {"popular" in plan && plan.popular ? " · Popular" : ""}
                </h3>
                <p>{plan.frequency}</p>
                <div className="price">
                  From ₹{plan.fromInr} <span>· hatchback / 30 days</span>
                </div>
              </article>
            ))}
          </div>
          <p style={{ marginTop: "1.25rem" }}>
            <a className="btn btn-dark" href="#contact">
              Subscribe in the app
            </a>
          </p>
        </div>
      </section>

      <section className="section" id="why">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">Why choose ZYLO</span>
            <h2>Built for Hyderabad parking realities.</h2>
          </div>
          <div className="grid-2">
            {whyZylo.map((item) => (
              <article className="panel" key={`why-${item.title}`}>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section" id="locations">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">Service locations</span>
            <h2>Hyderabad, Telangana — doorstep first.</h2>
            <p>
              Active service areas in the ZYLO platform. Confirm your exact
              address coverage when you book in the customer app.
            </p>
          </div>
          <div className="grid-3">
            {serviceAreas.map((area) => (
              <article className="panel" key={area}>
                <h3>{area}</h3>
                <p>Doorstep wash &amp; detailing · Hyderabad</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section faq" id="faq">
        <div className="shell">
          <div className="section-head">
            <span className="eyebrow">FAQs</span>
            <h2>Answers before you book.</h2>
          </div>
          {faqs.map((item) => (
            <details key={item.q}>
              <summary>{item.q}</summary>
              <p>{item.a}</p>
            </details>
          ))}
        </div>
      </section>

      <section className="section" id="contact">
        <div className="shell contact-box">
          <div className="section-head">
            <span className="eyebrow">Contact</span>
            <h2>Ready for a fresh start?</h2>
            <p>
              Booking is available in the ZYLO customer mobile app. A web
              customer portal at{" "}
              <a href="/app/">zyloo.co.in/app</a> is coming soon. For privacy
              and account requests, email{" "}
              <a href="mailto:support@zylo.app">support@zylo.app</a>.
            </p>
          </div>
          <div className="hero-actions">
            <a className="btn btn-dark" href="mailto:support@zylo.app">
              Email support
            </a>
            <a className="btn btn-ghost" href="/app/">
              Web booking — coming soon
            </a>
          </div>
        </div>
      </section>
    </>
  );
}

function PrivacyPage() {
  return (
    <article className="shell legal">
      <h1>Privacy Policy</h1>
      <p className="muted">
        Last updated: 20 October 2026 · ZYLO, Hyderabad, India · Contact:{" "}
        <a href="mailto:support@zylo.app">support@zylo.app</a>
      </p>
      <h2>1. What we collect</h2>
      <p>
        <strong>Account data:</strong> name, mobile number, email address (when
        you sign in with Phone, Email or Google via Firebase Authentication).{" "}
        <strong>Vehicles:</strong> nickname, make, model, colour and registration
        number you add. <strong>Addresses:</strong> service address and parking
        details needed to reach your car. <strong>Bookings:</strong> services
        booked, schedule, price paid, before/after service photos and ratings.{" "}
        <strong>Location:</strong> during an active job, our washing expert
        shares live location so you can track arrival; we do not track your
        personal location. <strong>Device data:</strong> basic app/device
        identifiers used for crash reporting and security.
      </p>
      <h2>2. How we use it</h2>
      <p>
        To create and service your bookings and subscriptions, assign a washing
        expert, process payments and refunds, send booking updates (SMS/push),
        provide support, prevent fraud and improve our service. We never sell
        your personal data.
      </p>
      <h2>3. Sharing</h2>
      <p>
        Your assigned washing expert sees your first name, vehicle details and
        service address/parking notes for the job. Payments are processed by our
        payment partner (Razorpay); we do not store card or UPI credentials. We
        use Firebase (Google) for authentication, database and hosting under
        their security standards. We may disclose data if required by law.
      </p>
      <h2>4. Data retention &amp; security</h2>
      <p>
        Booking and payment records are kept for accounting/legal purposes
        (typically 8 years for invoices); other profile data is kept while your
        account is active. Data is encrypted in transit (TLS) and
        access-controlled with Firebase Security Rules so users can only access
        their own data.
      </p>
      <h2>5. Your rights</h2>
      <p>
        You can view, edit or delete vehicles and addresses in the app anytime.
        For account deletion or data export, use Profile → Delete account or
        write to support@zylo.app; we action requests within 30 days, subject to
        legal retention duties.
      </p>
      <h2>6. Children</h2>
      <p>ZYLO is for users 18+. We do not knowingly collect data from children.</p>
      <h2>7. Changes</h2>
      <p>We will post changes on this page and update the date above.</p>
      <p>
        <Link to="/">← Back to home</Link>
      </p>
    </article>
  );
}

function TermsPage() {
  return (
    <article className="shell legal">
      <h1>Terms and Conditions</h1>
      <p className="muted">
        Last updated: 20 October 2026 · ZYLO, Hyderabad, India · Contact:{" "}
        <a href="mailto:support@zylo.app">support@zylo.app</a>
      </p>
      <h2>1. Service</h2>
      <p>
        ZYLO provides doorstep car washing and detailing in Hyderabad, India.
        Booking, payment and scheduling are completed through the ZYLO customer
        application. Service availability depends on location, slot capacity and
        society access rules.
      </p>
      <h2>2. Accounts</h2>
      <p>
        You must provide accurate contact and vehicle information. You are
        responsible for activity under your account. Accounts are for users aged
        18 and above.
      </p>
      <h2>3. Bookings &amp; cancellations</h2>
      <p>
        A booking is confirmed after successful payment verification where
        required. Cancellation and reschedule options shown in the app apply.
        Access delays caused by incomplete parking notes may affect service
        timing.
      </p>
      <h2>4. Payments</h2>
      <p>
        Prices are shown in the app before you pay. Payments are processed by
        Razorpay. Refunds, if applicable, follow the policy displayed at booking
        time and applicable law.
      </p>
      <h2>5. Conduct &amp; safety</h2>
      <p>
        You agree to provide lawful access to the vehicle location and accurate
        parking guidance. ZYLO experts may decline unsafe or inaccessible
        locations.
      </p>
      <h2>6. Liability</h2>
      <p>
        ZYLO takes reasonable care while servicing your vehicle. Claims related
        to service quality should be raised promptly through in-app support or
        support@zylo.app with booking details.
      </p>
      <h2>7. Changes</h2>
      <p>
        We may update these terms; the date above will change when we do. Continued
        use of ZYLO after updates constitutes acceptance of the revised terms.
      </p>
      <p>
        <Link to="/">← Back to home</Link>
      </p>
    </article>
  );
}

function NotFoundPage() {
  return (
    <div className="coming-soon">
      <div>
        <h1>Page not found</h1>
        <p className="lead">That URL is not part of the public ZYLO website.</p>
        <p style={{ marginTop: "1.25rem" }}>
          <Link className="btn btn-dark" to="/">
            Go home
          </Link>
        </p>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <>
      <ScrollToHash />
      <Header />
      <main>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </main>
      <Footer />
    </>
  );
}

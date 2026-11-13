/** Platform catalog from packages/shared-types — not invented marketing prices. */
export const packages = [
  {
    id: "body-wash",
    name: "Body Wash",
    blurb: "Exterior foam wash, tyre & rim clean, glass and microfibre dry with wax spray.",
    fromInr: 299,
  },
  {
    id: "interior",
    name: "Interior Cleaning",
    blurb: "Full vacuum, dashboard & console detailing, door pads and interior glass.",
    fromInr: 499,
  },
  {
    id: "deep-clean",
    name: "Deep Cleaning",
    blurb: "Complete inside-out detail — body wash, interior, seat shampoo and leather care.",
    fromInr: 999,
  },
] as const;

export const serviceAreas = [
  "Hitech City / Madhapur",
  "Gachibowli / Financial District",
  "Kondapur",
  "Banjara Hills",
  "Jubilee Hills",
  "Begumpet / Secunderabad",
] as const;

export const plans = [
  {
    id: "shine-8",
    name: "Shine 8",
    frequency: "8 visits · alternate days",
    fromInr: 1999,
  },
  {
    id: "shine-12",
    name: "Shine 12",
    frequency: "12 visits · every 2–3 days",
    fromInr: 2699,
    popular: true,
  },
  {
    id: "shine-daily",
    name: "Daily Shine",
    frequency: "26 visits · Mon–Sat recurring",
    fromInr: 3999,
  },
] as const;

export const howItWorks = [
  {
    step: "1",
    title: "Choose a package",
    text: "Pick a wash or detailing package that fits your car and schedule.",
  },
  {
    step: "2",
    title: "Share your location",
    text: "Add your address and parking notes so our expert can reach your car.",
  },
  {
    step: "3",
    title: "We come to you",
    text: "A trained washing expert arrives at your doorstep in Hyderabad.",
  },
  {
    step: "4",
    title: "Drive away fresh",
    text: "Pay securely in the ZYLO app and enjoy a clean, detailed car.",
  },
] as const;

export const whyZylo = [
  {
    title: "Doorstep convenience",
    text: "No queues, no drive-throughs — service happens where your car is parked.",
  },
  {
    title: "Clear packages",
    text: "Transparent service options from body wash to deep cleaning.",
  },
  {
    title: "Subscription shine",
    text: "Stay consistently clean with monthly wash plans in the ZYLO app.",
  },
  {
    title: "Built for Hyderabad",
    text: "Focused on apartment and gated-community parking across the city.",
  },
] as const;

export const faqs = [
  {
    q: "Where does ZYLO operate?",
    a: "ZYLO operates in Hyderabad neighbourhoods including Hitech City, Gachibowli, Kondapur, Banjara Hills, Jubilee Hills and Begumpet / Secunderabad. Exact coverage for your address is confirmed in the customer app.",
  },
  {
    q: "How do I book a wash?",
    a: "Download the ZYLO customer app on Android or iOS, add your vehicle and address, choose a package, and complete payment in the app. A web booking portal is planned for a future release.",
  },
  {
    q: "Do I need to be present?",
    a: "Provide clear parking and access notes when you book. Presence requirements depend on your society rules and the notes you leave for the expert.",
  },
  {
    q: "How are payments handled?",
    a: "Payments are processed securely through Razorpay inside the ZYLO customer app. Card and UPI credentials are not stored by ZYLO.",
  },
  {
    q: "Can I subscribe for regular washes?",
    a: "Yes. Shine 8, Shine 12 and Daily Shine plans are available in the ZYLO customer app so you can keep a consistent wash schedule.",
  },
] as const;

export const nav = [
  { href: "/#about", label: "About" },
  { href: "/#services", label: "Services" },
  { href: "/#packages", label: "Packages" },
  { href: "/#how", label: "How it works" },
  { href: "/#plans", label: "Plans" },
  { href: "/#locations", label: "Locations" },
  { href: "/#faq", label: "FAQs" },
  { href: "/#contact", label: "Contact" },
] as const;

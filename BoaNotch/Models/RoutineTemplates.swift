import Foundation

// MARK: - Input types

enum TemplateInputType {
    case freeText(placeholder: String)
    case picker(options: [String])
    case number(placeholder: String, defaultValue: Int?)
    case filePath(placeholder: String)
}

struct TemplateInput: Identifiable {
    let id: String
    let label: String
    let type: TemplateInputType
    let required: Bool
}

// MARK: - Template & Category

struct RoutineTemplate: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let schedule: String
    let deliver: String
    let inputs: [TemplateInput]
    let promptTemplate: String

    func composeDraft(values: [String: String]) -> String {
        var prompt = promptTemplate
        for (key, value) in values {
            prompt = prompt.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return "Schedule a new routine running \(schedule), delivered via \(deliver).\n\n\(prompt)"
    }
}

struct RoutineCategory: Identifiable {
    let id: String
    let icon: String
    let title: String
    let templates: [RoutineTemplate]
}

// MARK: - All categories

extension RoutineCategory {
    static let all: [RoutineCategory] = [personal, professional, research, travel, health, finance, creator]

    // MARK: Personal

    static let personal = RoutineCategory(id: "personal", icon: "sun.max", title: "Personal", templates: [
        RoutineTemplate(
            id: "morning-briefing",
            icon: "newspaper",
            title: "Morning Briefing",
            subtitle: "Daily news digest on your topics",
            schedule: "every day at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "topics", label: "Topics", type: .freeText(placeholder: "AI, cycling, French politics..."), required: true),
                TemplateInput(id: "city", label: "City (for weather)", type: .freeText(placeholder: "Paris"), required: false),
                TemplateInput(id: "tone", label: "Tone", type: .picker(options: ["concise", "detailed"]), required: true),
            ],
            promptTemplate: """
            Search the web for the latest news from the past 24 hours on these topics: {{topics}}.

            Find at least 5 recent articles per topic. Select the 3-5 most important stories overall.

            For each story:
            - A clear one-line headline
            - 2 sentences summarizing why it matters
            - Source URL

            End with a one-line weather summary for {{city}} today (temperature, rain yes/no, wind).

            Keep it {{tone}}. No preamble, start directly with the first story.
            """
        ),
        RoutineTemplate(
            id: "price-tracker",
            icon: "tag",
            title: "Price Tracker",
            subtitle: "Alert when a product drops below target price",
            schedule: "every day at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "product_name", label: "Product name", type: .freeText(placeholder: "MacBook Air M4"), required: true),
                TemplateInput(id: "product_url", label: "Product URL", type: .freeText(placeholder: "https://..."), required: true),
                TemplateInput(id: "target_price", label: "Target price", type: .freeText(placeholder: "999\u{20AC}"), required: true),
            ],
            promptTemplate: """
            Check the current price of "{{product_name}}" at this URL: {{product_url}}

            Use the browser to visit the page and extract the current price.

            If the price is at or below {{target_price}}, report:
            - Current price
            - Target price
            - The URL to buy

            If the price is above {{target_price}}, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "stock-alert",
            icon: "bag",
            title: "Stock / Restock Alert",
            subtitle: "Get notified when a product is back in stock",
            schedule: "every day at 10am and 4pm",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "product_name", label: "Product name", type: .freeText(placeholder: "PS5 Pro"), required: true),
                TemplateInput(id: "product_url", label: "Product URL", type: .freeText(placeholder: "https://..."), required: true),
            ],
            promptTemplate: """
            Check if "{{product_name}}" is currently in stock at: {{product_url}}

            Use the browser to visit the page. Look for availability indicators (add to cart button, "in stock" text, or similar).

            If the product appears available, report:
            - "{{product_name}} is back in stock"
            - The URL
            - The current price if visible

            If out of stock or unavailable, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "weekly-self-review",
            icon: "text.book.closed",
            title: "Weekly Self-Review",
            subtitle: "Sunday recap of your week with Hermes",
            schedule: "every Sunday at 7pm",
            deliver: "telegram",
            inputs: [],
            promptTemplate: """
            Search my recent Hermes sessions from the past 7 days using session search.

            Create a brief weekly summary:
            1. Main topics and projects I worked on
            2. Questions I asked most frequently
            3. Any recurring patterns or themes
            4. Things I started but might not have finished

            Keep it to 10-15 lines. Friendly tone, like a personal assistant recapping the week.
            """
        ),
    ])

    // MARK: Professional

    static let professional = RoutineCategory(id: "professional", icon: "briefcase", title: "Professional", templates: [
        RoutineTemplate(
            id: "competitor-watch",
            icon: "binoculars",
            title: "Competitor Watch",
            subtitle: "Weekly roundup of competitor activity",
            schedule: "every Monday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "competitors", label: "Competitors", type: .freeText(placeholder: "Notion, Linear, Coda..."), required: true),
                TemplateInput(id: "industry", label: "Industry", type: .freeText(placeholder: "productivity software"), required: true),
            ],
            promptTemplate: """
            Search the web for news and updates from the past 7 days about these companies: {{competitors}}.

            For each company, look for:
            - New product launches or feature announcements
            - Blog posts or press releases
            - Notable social media activity
            - Hiring trends or leadership changes

            Organize by company. For each item found:
            - One-line summary
            - Source URL
            - Date if available

            If nothing notable was found for a company, say "No significant updates this week."

            Industry context: {{industry}}. Prioritize items that could affect competitive positioning.
            """
        ),
        RoutineTemplate(
            id: "meeting-prep",
            icon: "calendar.badge.clock",
            title: "Meeting Prep",
            subtitle: "Morning briefing tailored to your workday",
            schedule: "every weekday at 7am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "calendar_context", label: "Meeting context", type: .freeText(placeholder: "Weekly product sync, 1:1 with CTO..."), required: true),
                TemplateInput(id: "focus_areas", label: "Focus areas", type: .freeText(placeholder: "AI features, pricing strategy..."), required: true),
            ],
            promptTemplate: """
            Today is a workday. Help me prepare for my day.

            My typical meeting context: {{calendar_context}}

            Search the web for any breaking news or recent developments related to: {{focus_areas}}.

            Provide:
            1. Top 3 things I should know before my meetings today (based on the topics above)
            2. For each item: what happened, why it matters, one talking point I could bring up
            3. A one-line reminder of anything time-sensitive

            Keep it scannable. No fluff. If nothing relevant happened, say "No major updates — you're up to speed" and respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "brand-mention-monitor",
            icon: "at",
            title: "Brand Mention Monitor",
            subtitle: "Track mentions of your brand across the web",
            schedule: "every day at 9am and 5pm",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "brand_names", label: "Brand names", type: .freeText(placeholder: "Acme Inc, Acme App, John Doe..."), required: true),
                TemplateInput(id: "ignore_sources", label: "Ignore sources (optional)", type: .freeText(placeholder: "reddit.com/r/spam..."), required: false),
            ],
            promptTemplate: """
            Search the web for recent mentions of: {{brand_names}}.

            Look across news sites, blogs, forums, and social media aggregators. Focus on mentions from the past 12 hours.

            For each mention found:
            - Source and URL
            - Brief quote or summary of what was said
            - Sentiment: positive, negative, or neutral

            Ignore results from these sources: {{ignore_sources}}.

            If no new mentions found, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "deadline-reminder",
            icon: "clock.badge.exclamationmark",
            title: "Deadline Reminder",
            subtitle: "Daily check on upcoming deadlines from a file",
            schedule: "every weekday at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "deadlines_file", label: "Deadlines file", type: .filePath(placeholder: "~/deadlines.md"), required: true),
            ],
            promptTemplate: """
            Read the file at {{deadlines_file}}.

            This file contains my upcoming deadlines in a simple format (date — description).

            Check today's date. For each deadline:
            - If it's today: mark as 🔴 URGENT
            - If it's within 3 days: mark as 🟡 APPROACHING
            - If it's within 7 days: mark as 🟢 UPCOMING
            - If further out: skip

            List only the relevant deadlines, sorted by urgency. For each one, include the date and how many days remain.

            If no deadlines are within 7 days, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "invoice-follow-up",
            icon: "doc.text.magnifyingglass",
            title: "Invoice Follow-Up",
            subtitle: "Track unpaid invoices and suggest follow-ups",
            schedule: "every Monday and Thursday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "invoices_file", label: "Invoices file", type: .filePath(placeholder: "~/invoices.md"), required: true),
            ],
            promptTemplate: """
            Read the file at {{invoices_file}}.

            This file tracks my sent invoices with: client name, amount, date sent, status (paid/pending).

            For each pending invoice:
            - Calculate how many days since it was sent
            - If 7+ days and unpaid: flag as "needs follow-up"
            - If 14+ days: flag as "overdue — send reminder"
            - If 30+ days: flag as "escalate"

            List only actionable items. For each, suggest a one-line follow-up message I could send.

            If all invoices are paid or too recent to follow up, respond with [SILENT].
            """
        ),
    ])

    // MARK: Research

    static let research = RoutineCategory(id: "research", icon: "magnifyingglass", title: "Research", templates: [
        RoutineTemplate(
            id: "arxiv-paper-watch",
            icon: "doc.text",
            title: "Arxiv / Paper Watch",
            subtitle: "Daily digest of new papers in your field",
            schedule: "every weekday at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "research_topics", label: "Research topics", type: .freeText(placeholder: "RLHF, tool-using agents..."), required: true),
                TemplateInput(id: "max_papers", label: "Max papers", type: .number(placeholder: "5", defaultValue: 5), required: false),
            ],
            promptTemplate: """
            Search the web for new academic papers published in the last 24 hours on: {{research_topics}}.

            Check arxiv.org, Google Scholar, and Semantic Scholar.

            Select the top {{max_papers}} most relevant papers. For each:
            - Title
            - Authors (first author + et al. if many)
            - One-paragraph summary of the contribution (what they did, what they found, why it matters)
            - Link

            If no new relevant papers were found today, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "topic-evolution-tracker",
            icon: "chart.line.uptrend.xyaxis",
            title: "Topic Evolution Tracker",
            subtitle: "Weekly update on how a topic is developing",
            schedule: "every Monday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "topic", label: "Topic", type: .freeText(placeholder: "EU AI Act"), required: true),
                TemplateInput(id: "angle", label: "Angle", type: .freeText(placeholder: "regulation, technical progress, market adoption..."), required: true),
            ],
            promptTemplate: """
            Search the web for developments in the past 7 days on: "{{topic}}" with a focus on {{angle}}.

            Provide:
            1. A 3-sentence summary of where things stand this week
            2. What changed compared to what was known before (new announcements, decisions, publications)
            3. Key quotes or positions from stakeholders (paraphrase, cite source)
            4. What to watch for next week

            This is a running tracker. Be factual. Distinguish between confirmed developments and speculation.
            """
        ),
        RoutineTemplate(
            id: "newsletter-digest",
            icon: "tray.full",
            title: "Newsletter Digest",
            subtitle: "Friday roundup of the week's best reads",
            schedule: "every Friday at 6pm",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "newsletter_topics", label: "Topics", type: .freeText(placeholder: "AI engineering, indie hacking..."), required: true),
                TemplateInput(id: "sources", label: "Preferred sources (optional)", type: .freeText(placeholder: "Hacker News, TLDR, Ben's Bites..."), required: false),
            ],
            promptTemplate: """
            Search the web for the most discussed and shared articles this week in these areas: {{newsletter_topics}}.

            Prioritize content from: {{sources}}.

            Compile a Friday digest with 5-7 items:
            - Headline
            - One-sentence summary
            - Why it was notable or widely shared
            - URL

            Group by topic area. End with a "rabbit hole of the week" — one longer read worth saving for the weekend.
            """
        ),
    ])

    // MARK: Travel

    static let travel = RoutineCategory(id: "travel", icon: "airplane", title: "Travel", templates: [
        RoutineTemplate(
            id: "flight-price-watch",
            icon: "airplane.departure",
            title: "Flight Price Watch",
            subtitle: "Daily check on flight prices for your trip",
            schedule: "every day at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "origin", label: "From", type: .freeText(placeholder: "Paris CDG"), required: true),
                TemplateInput(id: "destination", label: "To", type: .freeText(placeholder: "Tokyo NRT"), required: true),
                TemplateInput(id: "travel_dates", label: "Travel dates", type: .freeText(placeholder: "July 15-22"), required: true),
                TemplateInput(id: "max_price", label: "Max price", type: .freeText(placeholder: "800\u{20AC}"), required: true),
            ],
            promptTemplate: """
            Search the web for current flight prices from {{origin}} to {{destination}} around {{travel_dates}}.

            Check Google Flights, Skyscanner, or Kayak for the best available prices in economy class.

            Report:
            - Cheapest price found and airline
            - Whether this is a good price or not (compare to typical range if visible)
            - URL to book or continue searching

            If all prices are above {{max_price}}, respond with:
            "Still above {{max_price}}. Cheapest today: [price]."

            If a price is at or below {{max_price}}, respond with:
            "🎉 Price alert! [price] on [airline]. Book now: [url]"
            """
        ),
        RoutineTemplate(
            id: "pre-trip-checklist",
            icon: "checklist",
            title: "Pre-Trip Checklist",
            subtitle: "Daily countdown reminders before your trip",
            schedule: "every day at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "destination", label: "Destination", type: .freeText(placeholder: "Tokyo"), required: true),
                TemplateInput(id: "departure_date", label: "Departure date", type: .freeText(placeholder: "2026-07-15"), required: true),
                TemplateInput(id: "trip_type", label: "Trip type", type: .picker(options: ["beach", "city", "hiking", "business"]), required: true),
            ],
            promptTemplate: """
            Today's date is important. My trip to {{destination}} departs on {{departure_date}}.

            Calculate how many days until departure. Based on the countdown, give me ONE relevant reminder:

            14+ days out: "Check passport expiration. Verify visa requirements for {{destination}}."
            10 days: "Book airport transfer or parking. Check luggage weight limits."
            7 days: "Start packing list. Check weather forecast for {{destination}} during your stay."
            5 days: "Confirm accommodation booking. Download offline maps."
            3 days: "Check in online if available. Charge portable battery."
            2 days: "Pack. Check weather one more time for {{destination}}."
            1 day: "Final check: passport, tickets, charger, medications. Set out-of-office."
            0 days: "Bon voyage! Flight day. Leave early for the airport."

            Trip type: {{trip_type}} — adjust packing and prep suggestions accordingly.

            After departure day, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "destination-weather",
            icon: "cloud.sun",
            title: "Destination Weather",
            subtitle: "Daily weather forecast for your upcoming trip",
            schedule: "every day at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "destination", label: "Destination", type: .freeText(placeholder: "Tokyo"), required: true),
                TemplateInput(id: "departure_date", label: "Departure", type: .freeText(placeholder: "2026-07-15"), required: true),
                TemplateInput(id: "return_date", label: "Return", type: .freeText(placeholder: "2026-07-22"), required: true),
            ],
            promptTemplate: """
            Search the web for the current weather forecast in {{destination}} for the period {{departure_date}} to {{return_date}}.

            Provide:
            - Temperature range (high/low)
            - Rain probability
            - Wind conditions
            - A one-line packing recommendation (umbrella? layers? sunscreen?)

            If the forecast includes any extreme weather warnings or unusual conditions, highlight them.

            Keep it to 5 lines maximum.
            """
        ),
    ])

    // MARK: Health

    static let health = RoutineCategory(id: "health", icon: "heart", title: "Health", templates: [
        RoutineTemplate(
            id: "smart-break-reminder",
            icon: "figure.stand",
            title: "Smart Break Reminder",
            subtitle: "Varied break reminders every 2 hours",
            schedule: "every 2 hours on weekdays (10am-4pm)",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "style", label: "Style", type: .picker(options: ["gentle", "coach", "fun"]), required: true),
            ],
            promptTemplate: """
            Generate a unique break reminder. Never repeat the same message.

            Style: {{style}}.

            Include ONE of these (rotate, never the same two days in a row):
            - A 1-minute stretching suggestion (describe the stretch)
            - A hydration reminder with a fun fact about water
            - A breathing exercise (box breathing, 4-7-8, etc. — describe the steps)
            - An eye rest suggestion (20-20-20 rule or similar)
            - A posture check with a quick correction tip

            Keep it to 3-4 lines. Warm and human. Not corporate wellness spam.
            """
        ),
        RoutineTemplate(
            id: "weekly-meal-ideas",
            icon: "fork.knife",
            title: "Weekly Meal Ideas",
            subtitle: "Sunday meal plan with grocery list",
            schedule: "every Sunday at 10am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "preferences", label: "Preferences", type: .freeText(placeholder: "vegetarian, Mediterranean, quick meals under 30min..."), required: true),
                TemplateInput(id: "servings", label: "Servings", type: .number(placeholder: "2", defaultValue: 2), required: false),
            ],
            promptTemplate: """
            Suggest 5 dinner ideas for this week. Preferences: {{preferences}}. Servings: {{servings}}.

            For each meal:
            - Name
            - 2-3 main ingredients (things I might need to buy)
            - Estimated prep time
            - One-line description of the dish

            Vary the cuisine. Include at least one that works as leftovers for lunch the next day.

            End with a consolidated grocery list of items I probably need to buy (skip common pantry staples like oil, salt, pepper).
            """
        ),
    ])

    // MARK: Finance

    static let finance = RoutineCategory(id: "finance", icon: "chart.line.uptrend.xyaxis", title: "Finance", templates: [
        RoutineTemplate(
            id: "exchange-rate-alert",
            icon: "dollarsign.arrow.circlepath",
            title: "Exchange Rate Alert",
            subtitle: "Daily currency rate with threshold alerts",
            schedule: "every weekday at 8am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "from_currency", label: "From", type: .freeText(placeholder: "EUR"), required: true),
                TemplateInput(id: "to_currency", label: "To", type: .freeText(placeholder: "USD"), required: true),
                TemplateInput(id: "alert_threshold", label: "Alert threshold (optional)", type: .freeText(placeholder: "1.15"), required: false),
            ],
            promptTemplate: """
            Search the web for the current exchange rate from {{from_currency}} to {{to_currency}}.

            Report:
            - Current rate
            - Direction of change vs yesterday (up/down/stable)
            - Percentage change over the past week

            If the rate crosses {{alert_threshold}}, mark as "🎯 ALERT: threshold reached."

            Keep it to 3 lines. Just the numbers and direction.
            """
        ),
        RoutineTemplate(
            id: "portfolio-check",
            icon: "chart.bar",
            title: "Portfolio Check",
            subtitle: "Twice-daily snapshot of your assets",
            schedule: "every weekday at 8am and 6pm",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "assets", label: "Assets", type: .freeText(placeholder: "BTC, ETH, AAPL, MSFT, VOO"), required: true),
            ],
            promptTemplate: """
            Search the web for the current prices of: {{assets}}.

            For each asset:
            - Current price
            - 24h change (percentage and direction arrow ↑↓)
            - Any significant news in the last 12 hours that moved the price

            Format as a compact table. If nothing significant happened (all moves under 2%), just show the table.

            If any asset moved more than 5% in either direction, add a brief note explaining what happened.
            """
        ),
        RoutineTemplate(
            id: "subscription-renewal-tracker",
            icon: "creditcard",
            title: "Subscription Renewal Tracker",
            subtitle: "Weekly reminder of upcoming renewals",
            schedule: "every Monday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "subscriptions_file", label: "Subscriptions file", type: .filePath(placeholder: "~/subscriptions.md"), required: true),
            ],
            promptTemplate: """
            Read the file at {{subscriptions_file}}.

            This file lists my subscriptions with: service name, monthly/annual cost, renewal date.

            Check today's date. Flag any subscription renewing within the next 14 days:
            - Service name
            - Cost
            - Renewal date
            - Days until renewal

            If nothing renews within 14 days, respond with [SILENT].

            If something renews within 3 days, mark it 🔴 and ask: "Do you still want to keep [service]?"
            """
        ),
    ])

    // MARK: Creator

    static let creator = RoutineCategory(id: "creator", icon: "paintbrush", title: "Creator", templates: [
        RoutineTemplate(
            id: "trend-watch",
            icon: "flame",
            title: "Trend Watch",
            subtitle: "Twice-weekly trends in your creative domain",
            schedule: "every Monday and Thursday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "domain", label: "Domain", type: .freeText(placeholder: "UI design, photography..."), required: true),
                TemplateInput(id: "platforms", label: "Platforms", type: .freeText(placeholder: "Dribbble, Behance, Twitter..."), required: true),
            ],
            promptTemplate: """
            Search the web for trending topics, styles, and conversations in {{domain}} from the past 3-4 days.

            Check {{platforms}} and any relevant blogs, forums, or aggregators.

            Provide:
            1. Top 3 trends or hot topics (one-line each with context)
            2. One piece of inspiration (a notable project, post, or work that stood out)
            3. One emerging tool, technique, or resource worth knowing about

            Keep it to 10 lines. Be specific — names, links, examples. Not generic advice.

            If nothing notable happened, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "client-follow-up-coach",
            icon: "person.2",
            title: "Client Follow-Up Coach",
            subtitle: "Daily nudge to stay on top of client comms",
            schedule: "every weekday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "clients_file", label: "Clients file", type: .filePath(placeholder: "~/clients.md"), required: true),
            ],
            promptTemplate: """
            Read the file at {{clients_file}}.

            This file tracks my active clients with: name, last contact date, project status, next action.

            For each client where I haven't been in contact for 5+ days and the status is not "completed":
            - Client name
            - Days since last contact
            - A suggested follow-up message (1-2 sentences, professional and warm, based on the project status and next action noted)

            If all clients are up to date, respond with [SILENT].
            """
        ),
        RoutineTemplate(
            id: "content-idea-generator",
            icon: "lightbulb",
            title: "Content Idea Generator",
            subtitle: "Weekly content ideas based on real demand",
            schedule: "every Monday at 9am",
            deliver: "telegram",
            inputs: [
                TemplateInput(id: "niche", label: "Niche", type: .freeText(placeholder: "Swift development tutorials"), required: true),
                TemplateInput(id: "format", label: "Format", type: .picker(options: ["blog", "video", "social media"]), required: true),
                TemplateInput(id: "past_topics", label: "Already covered (optional)", type: .freeText(placeholder: "SwiftUI basics, async/await intro..."), required: false),
            ],
            promptTemplate: """
            Search the web for what people in the {{niche}} space are currently discussing, asking about, or struggling with.

            Check Reddit, Twitter/X, Stack Overflow, Hacker News, and relevant forums.

            Generate 5 content ideas for {{format}} format:
            - A catchy title
            - One-sentence angle (what makes this idea timely or unique)
            - Estimated audience interest (based on what you found: how many people seem to care)

            I've already covered: {{past_topics}}. Avoid duplicates.

            Prioritize ideas where demand is visible (people asking questions, threads with engagement) over generic evergreen topics.
            """
        ),
    ])
}

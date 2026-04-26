# Design System Specification: Urban Kinetic

## 1. Overview & Creative North Star: "The Kinetic Monolith"
The modern urban logistics landscape is a chaotic dance of movement, data, and physical goods. To represent this, this design system moves away from the "static grid" and toward **The Kinetic Monolith**. 

Our North Star is a high-end editorial approach to utility. We treat logistics data not as a spreadsheet, but as a premium magazine layout. We achieve this through "The Breathing Canvas"—using expansive white space, intentional asymmetry, and overlapping card structures that suggest movement. We move beyond "standard UI" by eliminating rigid borders in favor of tonal depth and layered surfaces, creating an interface that feels less like a tool and more like a high-performance dashboard for the city.

---

## 2. Color & Tonal Architecture
We utilize a sophisticated palette that shifts from the "Workhorse Blue" of logistics into a premium, deep-sea spectrum.

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders to section content. Boundaries must be defined strictly through background shifts. For example, a card using `surface_container_lowest` should sit atop a `surface_container_low` section. The contrast between these two tones is the only "border" allowed.

### Surface Hierarchy & Nesting
Treat the UI as physical layers of fine paper.
*   **Base:** `background` (#fbf9f8) - The foundational canvas.
*   **Sections:** `surface_container_low` (#f6f3f2) - Used for grouping related content blocks.
*   **Interactive Cards:** `surface_container_lowest` (#ffffff) - The highest "physical" layer for primary data.
*   **Deep Contrast:** `primary` (#003f87) - Reserved for high-importance focal points.

### The "Glass & Signature" Rule
*   **Glassmorphism:** For floating navigation or modals, use `surface` with a 70% opacity and a `20px` backdrop-blur. This ensures the urban map or data underneath "bleeds" through, maintaining context.
*   **Signature Textures:** For primary CTAs, do not use flat hex codes. Apply a subtle linear gradient from `primary` (#003f87) to `primary_container` (#0056b3) at a 135-degree angle to provide a "machined" professional finish.

---

## 3. Typography: Editorial Authority
We use **Manrope** exclusively. Its geometric yet humane construction bridges the gap between industrial efficiency and urban accessibility.

*   **Display (lg/md):** Used for "Big Data" moments—total deliveries, mileage, or efficiency percentages. These should be set with `-2%` letter spacing to feel "tight" and authoritative.
*   **Headlines (sm/md):** Your primary navigational anchors. Use `on_surface` (#1b1c1c).
*   **Title (md/sm):** For card headers. Always paired with `secondary` color icons for a sophisticated "muted" look.
*   **Body (lg/md):** Optimized for readability at `1rem`. Never use pure black; use `on_surface_variant` (#424752) to reduce eye strain during long-shift usage.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "software-standard." We use **Tonal Layering** to define importance.

*   **The Layering Principle:** To lift a "Current Shipment" card, place it on a `surface_container_high` background. The color shift creates the "lift," not a line.
*   **Ambient Shadows:** If a "floating" action is required (e.g., a New Order button), use a diffused shadow: `y: 8px, blur: 24px, color: rgba(0, 63, 135, 0.08)`. This mimics natural light reflecting off our primary blue.
*   **The "Ghost Border" Fallback:** If a container must exist on a similar-toned background (e.g., high-sunlight mobile environments), use `outline_variant` at **15% opacity**. It should be felt, not seen.

---

## 5. Components

### Cards & Lists (The Core)
*   **The Card:** Must use `DEFAULT` (8px) or `lg` (16px) corner radius. Forbid divider lines within cards. Use 16px or 24px of vertical white space to separate the header from the body content.
*   **Lists:** Items are separated by a shift to `surface_container` on hover/active states. No horizontal rules.

### Buttons
*   **Primary:** Gradient from `primary` to `primary_container`. White text. `xl` (1.5rem) roundedness for a pill-like, ergonomic feel.
*   **Secondary:** `surface_container_highest` background with `on_surface` text. No border.
*   **Tertiary:** No background. `on_primary_fixed_variant` text. High contrast, zero chrome.

### Input Fields
*   **State:** Use `surface_container_low` as the field background.
*   **Active:** Transition the background to `white` and add a `2px` "Ghost Border" using `primary`.
*   **Error:** Use `error` (#ba1a1a) for helper text and a subtle `error_container` tint for the field background.

### Logistics-Specific Components
*   **Status Badges:** Use `secondary_container` for background and `on_secondary_container` for text. The lack of "traffic light" colors (red/green) until an actual error occurs creates a calm, high-end environment.
*   **Route Progress:** Use a thick (4px) track of `surface_container_highest` with a `primary` fill. Rounded caps on both ends.

---

## 6. Do's and Don'ts

### Do:
*   **Do** use asymmetrical margins (e.g., 24px left, 16px right) on mobile to create an editorial "pull."
*   **Do** layer cards so they slightly overlap a hero background to suggest depth.
*   **Do** prioritize high contrast (WCAG AAA) for all typography on the move.

### Don't:
*   **Don't** use 1px dividers or "boxes inside boxes."
*   **Don't** use generic Material Design blue. Stick to the deep `primary` (#003f87).
*   **Don't** use "Drop Shadows" as a crutch for bad contrast. If the surface doesn't stand out, change the background tone.
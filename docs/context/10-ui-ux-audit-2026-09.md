# UI/UX Audit & Kế hoạch sửa — 09/2026

> **Dùng file này khi:** cần danh sách việc cụ thể để cải thiện giao diện/trải nghiệm và sửa các lỗi UI còn sót lại. File này **không lặp lại** các lỗi bảo mật/dữ liệu/RPC đã có ở `09-feature-audit-2026-09.md` — chỉ tập trung phần người dùng nhìn thấy và chạm vào (trừ 2 mục P0, vì chúng có triệu chứng UI trực tiếp).
>
> **Đã review với chủ dự án (2026-09-14):** nhiều mục dưới đây đã được chốt hướng hoặc bác bỏ sau khi trao đổi trực tiếp. Xem ghi chú "**Quyết định:**" ở từng mục.

**Phạm vi:** toàn bộ `src/views/*.vue`, `src/components/**/*.vue`, `index.html`, `src/assets/main.css`, đối chiếu với `brand-spec.md` và `docs/context/07-ui-ux-design.md`.

---

## 0. Đã xác nhận KHÔNG phải lỗi

- **Bottom nav "xếp chồng" trên mobile ở Session Detail — điều tra kỹ, xác nhận đây là hệ thống 3 lớp có chủ đích, không phải bug.** Cụ thể (`App.vue`, `SessionDetailView.vue` `<style scoped>`):
  - `BottomNav.vue`: `fixed inset-x-0 bottom-0 z-40` — thanh nav toàn app.
  - `.session-section-ribbon` (tab nhảy nhanh giữa các mục trong trang): `bottom: calc(65px + safe-area)`, `z-30` — nằm ngay trên BottomNav.
  - `.session-group-payment-bar` (thanh hành động "Thanh toán gộp", chỉ hiện khi admin chọn snapshot): `bottom: calc(135px + safe-area)`, `z-50` — nằm trên cùng, chỉ xuất hiện khi cần.
  - `App.vue` có hẳn 1 comment "Fixed-layer contract" ghi rõ thứ tự z-index, và `padding-bottom` của nội dung (`220px`) được tính để không bị 3 lớp này che. Toast cũng được dời lên `bottom: 148px` trên mobile để không bị che.
  - **Kết luận: đây là thiết kế offset thủ công có chủ đích, không chồng đè, không cần sửa.** Cách tốt hơn (một dock component tự tính offset động thay vì hardcode `65px`/`135px`) chỉ đáng làm nếu số lượng thanh cố định tăng thêm — hiện tại 2-3 thanh là ngưỡng vẫn ổn, không cần refactor bây giờ.
- **BUG-002 trong `08-bugs-and-roadmap.md` ("mobile layout vỡ") — đã sửa từ lâu, doc đang stale.** Đề xuất đánh dấu resolved trong doc đó khi tiện.
- **Kỷ luật màu (`indigo-600` duy nhất) và tap target (`min-h-11`, focus ring) đã tốt và nhất quán** — giữ nguyên pattern này cho component mới.

---

## 1. P0 — Quyền thao tác

### 1.1 `SessionDetailView.vue` — bảng thanh toán vẫn gate theo `isAuthenticated` thay vì `isAdmin`

**Quyết định:** giữ nguyên hướng sửa — đây đúng là điều cần sửa để đạt được đúng thứ chủ dự án muốn ("guest xem được, nhưng vài nút/tính năng bị vô hiệu hóa"). Sửa 5 chỗ:

- `SessionDetailView.vue:1665, 1703, 1813, 1866, 1952` — đổi `authStore.isAuthenticated` → `authStore.isAdmin`.

Route `/session/:id` **hiện đã không có guard chặn** (đúng ý muốn: guest xem được), vấn đề chỉ nằm ở việc một số nút hành động bên trong đang gate sai điều kiện.

### 1.2 Route `/sessions` (danh sách buổi) — thiếu lọc theo quyền, không phải thiếu route guard

**Quyết định (2026-09-14): guest chỉ thấy buổi đã kết thúc (`waiting_for_payment`/`done`), không thấy buổi đang `open`.**

Điều này đổi hướng sửa so với suy đoán ban đầu: **không** chặn route `/sessions` bằng `requiresAdmin` (làm vậy sẽ chặn luôn guest xem danh sách buổi đã xong, trái quyết định trên). Thay vào đó:

- `DashboardView.vue` hiện gọi thẳng `.from('view_session_summary').select('*')` không lọc gì — cần đổi để khi `!authStore.isAdmin`, luôn thêm điều kiện `status IN ('waiting_for_payment', 'done')` (chặn ở tầng query, không phải ẩn bằng CSS).
- Việc lọc này nên làm **cùng lúc** với việc chuyển sang gọi `search_sessions_list` (mục 2.8), vì RPC đó đã có sẵn tham số `p_status text[]` — chỉ cần frontend truyền `['waiting_for_payment','done']` khi không phải admin, để trống khi là admin.
- Nav tab "Sessions" ở `BottomNav.vue`/`AppHeader.vue`: **giữ hiện cho mọi người** (đúng, vì guest giờ được phép xem danh sách đã lọc) — không cần thêm điều kiện `isAdmin` như dự tính ban đầu. `docs/context/07-ui-ux-design.md:41` ghi "tab chỉ admin thấy" đang lệch với quyết định mới này — nên sửa dòng đó khi cập nhật doc 07.

---

## 2. P1 — Chức năng/UX

### 2.1 ~~Thiếu "điểm danh tất cả cho một người"~~ — KHÔNG PHẢI LỖI, ĐÃ RÚT KHỎI KẾ HOẠCH

**Quyết định của chủ dự án:** hành vi hiện tại đã tối ưu — `add_member_to_session_full_presence` tự tick present cho tất cả interval khi thêm member vào buổi; việc của admin là **bỏ tick** người vắng, không phải tick thủ công người có mặt. Vì đa số mọi người tham gia đủ buổi, thao tác bỏ tick số ít người vắng nhẹ hơn hẳn tick thủ công tất cả.

Ghi chú cho hồ sơ: đề xuất ban đầu bắt nguồn từ `docs/summary.md` (spec gốc, đã cũ) mô tả sai luồng ("bấm tên để tick tất cả"); doc sống thật (`docs/context/02-business-logic.md:241`) đã mô tả đúng RPC `add_member_to_session_full_presence` từ trước — không có drift ở tài liệu sống, chỉ có 1 file spec lịch sử bị lệch. Không cần sửa gì.

### 2.2 Ba ô "giá sân" khác nhau, dễ nhầm ở Create Session

**Bối cảnh chủ dự án cho biết:** chỉ 1 admin (chủ dự án) tạo/sửa mọi session; tất cả người khác là guest, chỉ trả tiền hoặc xem. Vì vậy đây là màn hình tần suất thấp, chỉ một người dùng hiểu rõ domain — ưu tiên là **làm rõ nhãn**, không cần đơn giản hoá cấu trúc dữ liệu.

**Đề xuất cụ thể:**
- Đổi nhãn `defaultCourtPrice` từ "Giá sân mặc định" → **"Giá sân/giờ (áp cho từng sân)"**.
- Đổi nhãn `courtFee` (courtFeeAddon) từ "Giá sân" → **"Phụ thu sân cố định (cộng thêm 1 lần/buổi)"** — tận dụng luôn `courtFeeAddonHint` đã có sẵn trong locale, hiện có vẻ chưa gắn vào UI (kiểm tra lại khi sửa).
- `p_price_per_hour` hardcode 0, không có ô nhập: vì tham số này hiện chết (không map field nào), đề xuất **xoá khỏi lời gọi RPC** thay vì để một tham số ẩn gây khó hiểu — nhưng đây là thay đổi chữ ký RPC, cần xác nhận không nơi nào khác phụ thuộc giá trị này trước khi xoá.

Việc này chỉ cần đổi nhãn/text, rủi ro thấp — có thể làm ngay không cần thêm quyết định.

### 2.3 Trùng UI cấu hình ngân hàng — đề xuất cụ thể

`stores/bankConfig.ts` (dùng bởi `SettingsView.vue`) và `composables/useBankConfig.ts` (dùng bởi `ProfileView.vue`, `PaymentView.vue`, `PaymentQRModal.vue`) là hai lớp state độc lập cho cùng bảng `bank_config`.

**Đề xuất:** giữ `useBankConfig.ts` (composable) làm nguồn duy nhất — nó đã được 3 nơi khác dùng, phạm vi ảnh hưởng nhỏ hơn khi đổi. Xoá `stores/bankConfig.ts`, chuyển `SettingsView.vue` sang gọi `useBankConfig()`. Composable cần bổ sung `deleteConfig`/`setDefault` nếu chưa có (kiểm tra khi implement) để tương đương chức năng store cũ.

### 2.4 Trùng UI xác nhận thanh toán tay — đề xuất cụ thể

`ManualPaymentModal.vue` (308 dòng, trang chi tiết buổi) và `CashPaymentModal.vue` (327 dòng, trang chủ) — giao diện khác nhau, cùng gọi RPC xác nhận thanh toán thủ công.

**Đề xuất:** gộp thành `ConfirmPaymentModal.vue` với prop `context: 'session' | 'home'` chỉ để đổi copy/label liên quan (ví dụ hiển thị tên buổi vs không), còn lại (input số tiền default = remaining, ghi chú, nút xác nhận, gọi RPC) dùng chung. Không đổi RPC.

### 2.5 `console.log` còn sót — giữ nguyên kế hoạch (agent decide, tiến hành như cũ)

`HomePage.vue:149, 158` — xoá 2 dòng.

### 2.6 Rác đã commit ở root repo — giữ nguyên kế hoạch (agent decide, tiến hành như cũ)

Xoá `false/`; chuyển các file `mobile-*.html`, `badminton-mobile-*.html` vào `docs/design-reference/` kèm ghi chú nguồn gốc, hoặc xoá nếu không còn cần.

### 2.7 [ĐÃ SỬA trong phiên audit này] Tính năng tiền cầu "không hoạt động"

Chủ dự án báo trực tiếp: tính năng tiền cầu chưa hoạt động, nút "Thêm loại cầu" không hoạt động. Điều tra theo quy trình root-cause (đọc code + query production read-only, không ghi gì vào DB):

- **Xác minh KHÔNG phải lỗi:** bảng `shuttle_types` tồn tại đúng trong production (migration `phase1_per_court_pricing_and_shuttle_tubes` đã apply), RLS 2 policy đúng như thiết kế (`shuttle_types_authenticated_read`, `shuttle_types_admin_write` check `members.user_id = auth.uid() AND role='admin'`), tài khoản admin duy nhất khớp `auth.users` đúng. Toàn bộ 16 key i18n `shuttle.*` cũng đã có đủ tiếng Việt lẫn tiếng Anh — không phải lỗi thiếu bản dịch như tôi nghi ban đầu (đã tự bác bỏ giả thuyết này sau khi đọc lại `messages.ts` kỹ hơn).
- **Root cause tìm được:** `shuttle_types` production đang có **0 dòng** (chưa từng thêm loại cầu nào thành công). Component `ShuttleUsageEditor.vue` (dùng trong Session Detail để ghi số cầu đã dùng) có nút **"Thêm loại cầu"** với hàm `addRow()` — hàm này lấy `activeTypes.value[0]`, nếu danh mục rỗng thì **`return` im lặng, không toast, không lỗi** (`ShuttleUsageEditor.vue:59-70`, trước khi sửa). Nút này dùng đúng chữ `t('shuttle.addType')` **giống hệt** nút thật để tạo loại cầu mới trong `/settings`. Nhiều khả năng chủ dự án đã bấm nhầm nút trong Session Detail (nút "thêm 1 dòng dùng cầu", cần danh mục có sẵn) tưởng là nút tạo danh mục cầu (chỉ có ở Settings) — hai nút trùng chữ nhưng khác chức năng.
- **Đã sửa:** `ShuttleUsageEditor.vue` — nút giờ tự disable + tooltip khi danh mục rỗng, kèm dòng hướng dẫn link thẳng tới `/settings` để tạo loại cầu đầu tiên. Thêm 2 key locale mới (`shuttle.noActiveTypes`, `shuttle.goToSettings`) cho cả vi/en. Đã chạy lại test suite (`ShuttleUsageEditor.test.ts`, 8/8 pass) và `vue-tsc --noEmit` (0 lỗi).
- **Chưa xác minh được (cần chủ dự án re-test):** nút "Thêm loại cầu" **thật** ở `/settings` (mục "Danh mục loại cầu") — có submit được không? Cấu trúc RLS/schema kiểm tra tĩnh đều ổn nên nhiều khả năng nó hoạt động bình thường và vấn đề chỉ là nhầm nút như trên. Nếu sau khi thử đúng ở `/settings` vẫn không tạo được loại cầu nào, cần báo lại **thông báo lỗi chính xác** (toast hiện chữ gì, hay console có lỗi gì) để điều tra tiếp — tĩnh không thể tìm thêm được nữa.

### 2.8 [MỚI] Filter/search cho danh sách buổi, hỗ trợ tìm theo người cho guest

RPC `search_sessions_list` đã tồn tại trong DB (`docs/context/02-business-logic.md:183-204`) — fuzzy search theo `title` (pg_trgm), filter theo `status[]`, khoảng ngày, cursor pagination — nhưng **frontend chưa từng gọi nó** (đã ghi nhận từ `09-feature-audit`).

Chủ dự án muốn thêm: filter cho danh sách buổi, và **filter theo người tham gia** cho guest, có fuzzy search.

**Việc cần làm (2 phần, backend trước):**
1. **Backend:** `search_sessions_list` hiện KHÔNG có tham số lọc theo thành viên. Cần thêm `p_member_query text` (fuzzy match `members.display_name` của người có trong `session_registrations` của buổi đó qua `EXISTS`/`JOIN`), tương tự cơ chế fuzzy đang dùng cho `title`.
2. **Frontend:** thay lệnh gọi thẳng `view_session_summary` trong `DashboardView.vue` bằng `search_sessions_list`, thêm 2 ô: search theo tên buổi (đã có RPC hỗ trợ), search theo tên người chơi (RPC cần bổ sung ở bước 1). Infinite scroll qua cursor đã có sẵn thiết kế trong RPC. Khi gọi với vai trò guest, luôn truyền `p_status: ['waiting_for_payment', 'done']` (xem 1.2); khi admin, để trống để thấy mọi trạng thái.

### 2.9 [MỚI, ĐÃ CHỐT] Quản lý loại cầu — giữ nguyên trong `/settings`, không cần tab mới

Chủ dự án nói trang admin "không có trang tổng để quản lý" loại cầu — kiểm tra lại thấy **đã có**: mục "Danh mục loại cầu" trong `/settings` (route đã `requiresAuth+requiresAdmin`), qua `useShuttleTypes.ts` (thêm, sửa, bật/tắt hoạt động — soft-delete kiểu `is_active`, không có hard delete, nhất quán với phần còn lại của app).

**Quyết định (2026-09-14): giữ nguyên trong `/settings`, không tách tab riêng.** Không cần làm gì thêm cho mục này.

### 2.10 [MỚI] `PaymentView.vue` (link thanh toán công khai) và `LoginView.vue` thừa hưởng full chrome không cần thiết

`App.vue` render `AppHeader` + `BottomNav` không điều kiện cho **mọi route**, kể cả `/pay` (link chia sẻ công khai qua Zalo/SMS cho người lạ, không có lý do gì để thấy tab Home/Members/Sessions của app nội bộ) và `/login`. Đáng chú ý: `PaymentView.vue` là file DUY NHẤT có class `dark:` (18 chỗ) trong toàn bộ app — dấu hiệu cho thấy nó vốn được thiết kế như một trang độc lập, không phải trang con của app shell.

**Đề xuất:** thêm cơ chế route-level ẩn chrome (`meta.hideChrome: true` cho `/pay`), giữ `/login` như hiện tại (chrome ở đây không gây hại, chỉ là dư thừa nhẹ).

---

## 3. P2 — Nhất quán thị giác (giữ nguyên toàn bộ kế hoạch cũ, "agent decide")

Không đổi so với bản trước — amber/yellow drift + StatusBadge dùng chung, debt badge ẩn dưới 640px, logo SVG chép tay + emoji 🚫, focus ring ô tìm kiếm, `dark:` cô lập ở PaymentView (xem thêm mục 2.10 — nay có thêm lý do để xử lý đồng thời), thiếu `lang="vi"`, brand-spec.md lệch thực tế (xem câu hỏi cuối file), comment thừa ở CourtBookingEditor.

---

## 4. Kế hoạch triển khai (cập nhật)

**Đã xong:**
- ✅ `fix(ui): guard shuttle usage add-row when catalogue is empty, add settings deep-link` (mục 2.7)

**Đợt 1 — quyền thao tác**
- `fix(ui): gate payment table actions in SessionDetailView on isAdmin, not isAuthenticated` (1.1)
- `fix(ui): filter session list to finalized-only for non-admin` (1.2 — không guard route, chỉ lọc status theo quyền; làm chung với 2.8)

**Đợt 2 — dọn nợ hiển thị**
- `fix(ui): remove stray console.log from HomePage` (2.5)
- `chore: remove committed pnpm litter and relocate/remove root prototype HTML files` (2.6)
- `fix(ui): normalize search input focus ring, swap emoji/hand-drawn icon for lucide-vue-next` (3.4-3.6 cũ)

**Đợt 3 — hợp nhất trùng lặp + làm rõ nhãn**
- `fix(ui): clarify the three court-price field labels on Create Session` (2.2)
- `refactor(ui): unify bank-config store/composable into one source` (2.3)
- `refactor(ui): merge CashPaymentModal and ManualPaymentModal into one component` (2.4)
- `refactor(ui): extract shared StatusBadge/statusColors, fix amber/yellow drift` (P2)

**Đợt 4 — tính năng mới**
- `feat(db): extend search_sessions_list with member-name fuzzy filter` + `feat(ui): wire session list to search_sessions_list with title/person filters, finalized-only for guest` (2.8, gộp với 1.2)

**Đợt 5 — polish còn lại**
- `fix(ui): hide app chrome on /pay via route meta` (2.10)
- `fix(ui): show compact debt badge below 640px in AppHeader`
- `fix(ui): strip stray dark: classes from PaymentView` (gộp chung với 2.10)
- `fix(a11y): set lang="vi" on index.html`
- ✅ `chore(docs): reconcile brand-spec.md with actual main.css/reality` — đã làm (xem mục 5)
- `chore(docs): mark docs/context/08 BUG-002 resolved, fix docs/context/07 "Sessions tab admin-only" line to match 1.2`
- `chore: trim stale comment referencing deleted SessionHeader.vue`

**Đợt 6 — edge case từ audit sâu (mục 6), ưu tiên P1 trước**
- `fix(auth): store in-flight initialize() promise so router guard awaits real session restore`
- `feat(ui): add success/refresh state to public PaymentView poll`
- `feat(ui): surface realtime disconnect state in SessionDetailView with reconnect refetch`
- `fix(ui): warn on duplicate display_name when adding a member`
- `fix(ui): replace window.confirm/alert with app modal/toast pattern` (ProfileView, MemberView, PaymentView)
- `refactor(ui): add toFriendlyError() helper, replace raw error.message across LoginView/MemberView/MemberDetailView`
- `fix(ui): add empty-state row to MemberDetailView desktop table`
- `chore: type selectedSnapshot properly in MemberDetailView; note dead getShortName() in formatters.ts`

---

## 5. Quyết định đã chốt (2026-09-14)

1. **Phạm vi session hiển thị cho guest ở `/sessions`:** chỉ buổi đã `waiting_for_payment`/`done`. Chi tiết thực thi ở mục 1.2/2.8.
2. **`brand-spec.md`:** viết lại theo best practice cho một internal tool đã nhất quán sẵn — không thêm lớp token màu/font mới (không có nhu cầu thực tế, chỉ là refactor không lý do), rewrite doc để khớp thực tế (Tailwind default type scale, không custom font-family, `indigo-600` accent duy nhất). **Đã cập nhật `brand-spec.md`.**
3. **Loại cầu:** giữ nguyên trong `/settings`. Không cần làm gì thêm.

---

## 6. Đợt audit sâu hơn — edge case mới phát hiện

Theo yêu cầu "audit kĩ hơn" — pass thứ 3, tập trung form/validation, loading/empty/error state, concurrency, i18n, formatter, và đọc kỹ `PaymentView.vue`/`LoginView.vue`. Không lặp lại 2 pass trước.

### P1 — ảnh hưởng thật

- **`src/stores/auth.ts:41-44` — race condition trong `initialize()`.** Guard chống gọi trùng (`if (isInitialized) return`) trả về ngay thay vì trả lại promise đang chạy. `router/index.ts:68-70` gọi `await authStore.initialize()` mỗi khi `authStore.loading = true`, kỳ vọng đợi tới khi session restore xong — nhưng nếu `App.vue:9` đã gọi `initialize()` thật trước đó vài microtask, lần gọi thứ hai từ router hit early-return và resolve ngay lập tức, khiến router guard đọc `isAuthenticated`/`isAdmin` **trước khi** `supabase.auth.getSession()` xong. **Hậu quả cụ thể:** F5 (hard refresh) ở `/settings` hoặc `/create-session` có thể đá admin đang đăng nhập thật về `/login`. Không phải lỗ hổng bảo mật (state mặc định fail-closed, không fail-open), nhưng gây khó chịu/mất niềm tin vào app. **Fix:** lưu promise đang chạy (`let initPromise: Promise<void> | null`), guard trả về promise đó thay vì `return` trơn.
- **`PaymentView.vue` — trang thanh toán công khai không có trạng thái "thành công".** Không polling gì cả (chỉ `PaymentQRModal` ở nơi khác mới polling) — spinner "Chờ thanh toán" (`:117-141`) là trạng thái duy nhất, không bao giờ chuyển thành công dù đã trả tiền xong. Người trả tiền qua link chia sẻ, chuyển khoản xong, quay lại tab vẫn thấy "Chờ thanh toán" mãi. **Fix:** thêm polling nhẹ (hoặc tối thiểu nút "Tôi đã chuyển khoản, kiểm tra lại") để trang này có thể tự chuyển sang trạng thái thành công.
- **`SessionDetailView.vue:833-888` — kênh realtime không có status callback.** `.channel(...).subscribe()` không bắt `CHANNEL_ERROR`/`TIMED_OUT`/`CLOSED`. Mất kết nối (tab chạy nền, wifi chập chờn) khiến điểm danh/thanh toán trực tiếp ngừng cập nhật **im lặng** — admin tưởng thiết bị khác không thao tác gì. **Fix:** thêm callback trạng thái, hiện banner nhỏ "mất kết nối trực tiếp, đang thử lại" khi không phải `SUBSCRIBED`, gọi lại `fetchData()` khi reconnect.
- **`MemberView.vue:50-86` `addMember()` — không kiểm tra trùng `display_name`.** Hai thành viên tên "Nguyễn Anh" có thể cùng tồn tại; mọi màn hình khác (tìm kiếm, bảng nợ, chọn người đăng ký buổi) phân biệt người chỉ bằng `display_name` — admin có thể thu tiền/gán nợ nhầm người trùng tên. **Fix:** cảnh báo trùng tên (so khớp không phân biệt hoa/thường với danh sách đã tải) trước khi insert, hoặc ràng buộc unique ở DB nếu muốn chặn hẳn.

### P2 — polish/nhất quán

- **`window.confirm()` còn dùng** ở `ProfileView.vue:106`, `MemberView.vue:90` — thay bằng modal cùng kiểu với modal xác nhận thanh toán đã có.
- **`alert()` thô ở trang công khai** `PaymentView.vue:66` (fallback khi `navigator.share` không có) — đổi sang `vue-toastification` cho khớp phần còn lại của cùng file.
- **Lỗi backend thô hiển thị thẳng cho người dùng** (pattern lặp lại, không phải 1 chỗ) — `LoginView.vue:40`, `MemberView.vue:82,104,145`, `MemberDetailView.vue:91,192`: `error.message` từ Supabase/Postgres (tiếng Anh) hiện thẳng ra giữa 1 app toàn tiếng Việt. **Fix:** viết 1 helper `toFriendlyError(error)` map các mã lỗi Supabase phổ biến sang tiếng Việt, fallback về thông báo chung thay vì `error.message`.
- **`MemberDetailView.vue:404-523` — bảng desktop thiếu empty state.** Chỉ nhánh mobile (`:305`) check `sessions.length === 0`; member chưa có lịch sử buổi nào xem trên desktop thấy bảng chỉ có header, trông như đang treo. **Fix:** thêm dòng empty-state giống bản mobile vào `<tbody>` desktop.
- **`MemberDetailView.vue:27`** — `selectedSnapshot = ref<any>(null)` kèm comment tự nhận là workaround. Chưa gây lỗi thật, nhưng field nào modal cần thêm sau này sẽ fail âm thầm không cảnh báo compile-time. **Fix:** gán type thật thay vì `any`.
- **`src/utils/formatters.ts:5-10` `getShortName()`** — dead code (0 nơi gọi), code còn mâu thuẫn với chính docstring của nó (hứa rút gọn tên đệm nhưng thực ra chỉ cắt 3 từ đầu). Không ảnh hưởng gì vì không ai gọi — nêu ra để không ai lỡ dùng nhầm sau này, không tự xoá vì không ai yêu cầu.

**Nhận xét chung:** luồng tiền/điểm danh chính đã chắc chắn (dual layout mobile/desktop nhất quán, tap target/focus ring tốt, màu accent kỷ luật). Các lỗ hổng tìm được ở đây tập trung vào đường lỗi/edge case (lỗi backend thô, thiếu empty state, mất kết nối realtime im lặng) — ổn trên happy path nhưng bỏ rơi người dùng khi có sự cố — và 1 race condition thật trong auth init.

---

## 7. Ngoài phạm vi audit này

- Đúng đắn dữ liệu, RPC, bảo mật RLS: xem `docs/context/09-feature-audit-2026-09.md`.
- Mô hình giá theo sân/khung giờ, tiền cầu theo ống: đã có schema (`shuttle_types`, `shuttle_usage`) và UI (`ShuttleUsageEditor.vue`) — cần chủ dự án re-test luồng tạo loại cầu ở `/settings` trước khi coi tính năng này là "đã xong".

# Phase P0 — Sửa 2 lỗ hổng phân quyền admin ở luồng session

> Phạm vi thu hẹp từ `docs/context/10-ui-ux-audit-2026-09.md` mục 1.1 và 1.2, sau khi đã chốt hướng với chủ dự án ngày 2026-09-14. Chỉ 2 việc trong tài liệu này thuộc plan — các mục khác trong file 10 (P1/P2, tính năng filter mới, refactor trùng lặp) là các plan riêng sau này.

## Bối cảnh

Chủ dự án muốn: guest (kể cả chưa đăng nhập) xem được session list và session detail, nhưng các nút/tính năng chỉ admin mới được dùng phải bị vô hiệu hóa cho non-admin. Hiện có 2 chỗ code không khớp ý này.

## Yêu cầu 1 — `SessionDetailView.vue`: bảng thanh toán đang gate nhầm điều kiện

**Hiện trạng (bug):** 5 chỗ trong khu vực bảng thanh toán/snapshot đang kiểm tra `authStore.isAuthenticated` (chỉ cần đăng nhập) thay vì `authStore.isAdmin` (phải là admin). Vì hiện tại chỉ có đúng 1 tài khoản (vừa là admin), bug này chưa từng bị khai thác, nhưng bất kỳ tài khoản non-admin nào đăng nhập sau này sẽ thấy và bấm được các action chỉ admin được phép dùng (chọn snapshot để tạo QR gộp, xác nhận thu tiền mặt qua `SessionExtraCharges`).

**5 vị trí cần sửa** (`src/views/SessionDetailView.vue`):
- Dòng 1665: prop `:isAdmin="authStore.isAuthenticated"` truyền vào `<SessionExtraCharges>`.
- Dòng 1703: checkbox chọn snapshot (bản mobile) — `v-if="snapshot.status !== 'paid' && authStore.isAuthenticated"`.
- Dòng 1813: cột checkbox trong `<thead>` bảng desktop — `v-if="authStore.isAuthenticated"`.
- Dòng 1866: ô checkbox trong `<tbody>` bảng desktop — `v-if="authStore.isAuthenticated"`.
- Dòng 1952: `:colspan="authStore.isAuthenticated ? 6 : 5"` của dòng "Quỹ tồn".

**Không đổi:** dòng 191 và 735 (`if (!authStore.isAuthenticated) return t.value('session.readOnlyHint')`) — đây là hint hiển thị cho người xem chưa đăng nhập, không phải gate hành động admin, giữ nguyên `isAuthenticated`.

**Acceptance criteria:**
- Một tài khoản đã đăng nhập nhưng KHÔNG phải admin: không thấy checkbox chọn snapshot (cả bản mobile lẫn desktop), không thấy cột checkbox trong header bảng desktop, colspan dòng quỹ tồn là 5, và `SessionExtraCharges` nhận `isAdmin=false`.
- Admin: mọi hành vi trên giữ nguyên như trước (checkbox hiện, cột hiện, colspan 6, `isAdmin=true`).
- Guest hoàn toàn chưa đăng nhập: vẫn xem được bảng thanh toán (tên, số tiền, trạng thái) — không có gate route nào chặn, hành vi giống hệt tài khoản non-admin ở trên.

## Yêu cầu 2 — `DashboardView.vue`: danh sách session không lọc theo quyền

**Hiện trạng (bug):** `fetchSessions()` gọi `.from('view_session_summary').select('*').order(...)` không lọc gì — non-admin (kể cả guest chưa đăng nhập) thấy TẤT CẢ session kể cả đang `open` (chưa chốt sổ, số liệu có thể còn đang sửa).

**Quyết định sản phẩm (2026-09-14):** non-admin chỉ thấy session có `status` là `waiting_for_payment` hoặc `done`. Admin thấy tất cả (kể cả `open`, `cancelled`).

**Thực thi:** thêm điều kiện lọc vào query hiện có khi `!authStore.isAdmin` — dùng `.in('status', ['waiting_for_payment', 'done'])` trên chính query `view_session_summary` đang có. **Không** làm route guard (`meta.requiresAdmin`) — route `/sessions` vẫn mở cho mọi người, chỉ lọc dữ liệu trả về. Đây là bản tối giản của mục 2.8 trong `docs/context/10-ui-ux-audit-2026-09.md`; việc chuyển sang RPC `search_sessions_list` (fuzzy search theo tên buổi/người chơi) là một plan riêng sau này, không nằm trong plan này.

**Acceptance criteria:**
- Admin gọi `fetchSessions()`: không có filter `status`, thấy mọi trạng thái (giữ nguyên hành vi cũ).
- Non-admin (kể cả chưa đăng nhập) gọi `fetchSessions()`: query có filter `.in('status', ['waiting_for_payment', 'done'])`.
- Nav tab "Sessions" ở `BottomNav.vue`/`AppHeader.vue`: không đổi gì — tiếp tục hiện cho mọi người (đã đúng từ trước, không phải bug).

## Ngoài phạm vi (deliberately out of scope)

- RPC `search_sessions_list` (fuzzy search theo người chơi, cursor pagination) — plan riêng.
- Mọi mục P1/P2 khác trong `docs/context/10-ui-ux-audit-2026-09.md` (trùng lặp UI, race condition auth, PaymentView polling, v.v.) — plan riêng.

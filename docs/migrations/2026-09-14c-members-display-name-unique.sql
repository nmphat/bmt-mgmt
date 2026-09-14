-- Chặn trùng tên thành viên ở tầng DB (không phân biệt hoa/thường, đã trim khoảng trắng).
-- Bối cảnh: 2 dòng "kiều phương " / "kiều phương" (khác nhau 1 dấu cách) là cùng 1 người,
-- đã bị tạo trùng vì FE trước đây chỉ validate .trim() nhưng không lưu giá trị đã trim.
-- FE đã sửa (MemberView.vue: trim + check trùng tên trước khi insert/update).
-- Migration này là lớp phòng thủ thứ hai ở DB, chặn cả các đường ghi không qua FE (API trực tiếp).
--
-- BẮT BUỘC: chạy migration này SAU KHI đã merge/xóa các dòng trùng tên hiện có.
-- Nếu còn dữ liệu trùng, CREATE UNIQUE INDEX bên dưới sẽ tự báo lỗi
-- "could not create unique index ... contains duplicate key values" — dọn xong rồi chạy lại.

CREATE UNIQUE INDEX IF NOT EXISTS members_display_name_unique_idx
  ON public.members (lower(trim(display_name)));

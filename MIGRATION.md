# Migration Map — WebIndex (Python/JSON) → Seovivu (Phoenix/Postgres)

Nguồn dữ liệu cũ: `/Users/thangnguyen/Desktop/webindex-refactor/WebIndexUrl/*.json`
Đích: dự án Phoenix `seovivu` (Postgres + Ecto, auth Telegram-first, ví credit).

> Mục đích file này: **liệt kê các phần CÓ THỂ migrate** để bạn chọn. Chưa thực thi gì cả.
> Đánh dấu phần bạn muốn làm rồi tôi sẽ viết script migrate.

---

## ✅ Migrate được NGAY (ưu tiên cao)

### 1. Người dùng — `users_db.json` (326 users) → bảng `users`
Đây là phần quan trọng nhất, map gần như 1:1 vì **cả hai hệ thống đều Telegram-first**.

| Field cũ (JSON) | Field mới (`Seovivu.Accounts.User`) | Ghi chú |
|---|---|---|
| `username` | `username` | trùng |
| `telegram_id` | `telegram_id` (unique, NOT NULL) | 325/326 có; **1 user (`admin12`) có telegram_id=0** → cần xử lý riêng |
| `telegram_username` | `telegram_username` | trùng |
| `telegram_first_name` | `telegram_first_name` | trùng |
| `telegram_last_name` | `telegram_last_name` | trùng |
| `level` = admin | `role` = `:admin`, else `:user` | chỉ `admin12` là admin |
| (mặc định) | `status` = `:active` | không có ai bị ban trong data |
| `created_at` | `inserted_at` | parse `"YYYY-MM-DD HH:MM:SS"` → utc_datetime |
| `telegram_updated_at` | `last_login_at` (gần nhất có thể) | hoặc bỏ |

**Lưu ý mật khẩu:** 325/326 user có field `password` là **JWT token, KHÔNG phải mật khẩu thật** → không thể tái dùng. Hệ thống mới dùng **bcrypt + Telegram**. Phương án:
- (A) Migrate user, **sinh mật khẩu mới** rồi DM lại qua bot khi họ `/start` (giống flow đăng ký mới). ← khuyến nghị
- (B) Đặt mật khẩu random, để user bấm `/reset` trên bot.

Không có telegram_id trùng → an toàn dùng làm khóa định danh.

---

### 2. Hạng/Tier + Credit → `wallets` + `packages` (Catalog/Billing)
Hệ cũ dùng **level theo tên** (`Free/Basic/VIP/Sliver/Gold/Diamond`). Hệ mới dùng **ví credit + gói (package) có credits/days/price**. Cần map khái niệm.

**Phân bố level hiện tại:** Basic 298, Free 13, VIP 9, Diamond 3, Gold 1, Sliver 1, admin 1.

**Credit/tháng theo tier (`settings_db.json`):**
| Tier | credit_per_month |
|---|---|
| basic | 0 |
| vip | 5 000 |
| sliver | 20 000 |
| gold | 50 000 |
| diamond | 100 000 |

→ Việc migrate:
1. Tạo sẵn các `packages` tương ứng (Basic/VIP/Silver/Gold/Diamond) với `credits` = số ở trên, `days` = 30.
2. Với mỗi user có `expiry_date` (50 users) → set `wallets.expires_at`.
3. Nạp `wallets.credits` từ field `credit` của user (14 users có credit>0) hoặc theo gói.
4. Ghi 1 `ledger_entry` reason=`upgrade`/`admin_adjust` để có audit.

> ⚠️ Đây là phần cần bạn quyết định **business mapping** (1 tier = mấy credit, còn hạn bao lâu). Tôi sẽ làm theo bảng bạn chốt.

---

### 3. Lịch sử đăng nhập — `login_history_log.json` (970 dòng) → `login_logs`
| Field cũ | Field mới (`Accounts.LoginLog`) |
|---|---|
| `username` → resolve `user_id` | `user_id` |
| `ip` | `ip_address` |
| (không có) | `user_agent` = null |
| `login_time` | `inserted_at` |

Migrate được trực tiếp (chỉ cần map username → user_id).

---

### 4. Dự án Submit Index — `project_submit_log.json` (80) + `projects_db.json` (7) → `index_projects` + `index_project_urls`
Khớp với context **Indexer** của hệ mới (feature `submit_index`).

| Field cũ | Field mới (`Indexer.Project` / `ProjectUrl`) |
|---|---|
| `name` | `project.name` |
| `owner` → user_id | `project.user_id` |
| `created_at` | `project.inserted_at` |
| `status` (processing/completed) | `project.status` (`submitted`/`processing`/`done`) |
| `urls[]` | mỗi URL → 1 `index_project_urls` row, `status=pending` |
| len(urls) | `project.url_count` |

---

## 🟡 Migrate được nhưng cần thêm bảng / quyết định

### 5. Cấu hình hệ thống — `settings_db.json` (39 keys) → `settings` (key/value map)
Bảng `settings` mới là key→map linh hoạt. Có thể đổ toàn bộ vào, NHƯNG nhiều key cũ là **giới hạn theo tier** (`url_limit_per_project_vip`...) — hệ mới đã chuyển sang mô hình credit nên phần lớn **không còn áp dụng**. Khuyến nghị: chỉ migrate các key còn ý nghĩa (`worker_threads`, `delay_api`...) và map credit_per_month sang packages (mục 2).

### 6. Mẫu tin nhắn Telegram — `messages_config.json` (9 templates) → `settings` (Telegram message templates)
`register_success`, `vip_upgrade`, `account_banned`, `system_error`... Hệ mới có template tin nhắn editable trong `settings`. Map được nhưng nội dung tier-based cần viết lại theo mô hình credit.

### 7. Telegram bot config — `telegram_config.json` (token, bot_id) → `settings`/ENV
Token & bot_id → đưa vào settings hoặc biến môi trường. 1 dòng config.

### 8. Proxy backlink — `backlink_proxy_keys.json` (17 proxies `host:port:user:pass`) → `proxies`
Parse được sang `Net.Proxy` (protocol/host/port/username/password). `proxy_keys.json`, `serper_keys.json`, `api_keys.json` → lưu vào `settings` dạng key list.

---

## 🔴 KHÔNG khuyến nghị migrate (hệ mới chưa có feature / dữ liệu rác)

| File | Lý do |
|---|---|
| `domain_projects_db.json` (40) | Feature "domain check" — **hệ mới chưa có context tương ứng** (Seo.Job có check_index/url_status/backlink/redirect_301/submit_index, không có domain-project). Cần build feature trước. |
| `duplicate_projects_db.json` (54) | Feature "duplicate content check" — **hệ mới chưa có**. Chứa cả html_content lớn. |
| `backlink_data.json` (764K), `backlink_jobs.json` (9.3M) | Kết quả job backlink cũ — dữ liệu vận hành tạm, hệ mới chạy job riêng (`seo_jobs`). Không cần lịch sử. |
| `user_url_log.json` (3234) | Thống kê đếm URL/ngày — chỉ là số liệu usage, hệ mới đã có `ledger_entries`/`seo_jobs` để tính. Có thể bỏ. |
| `affiliate_db.json` (23) | **Hệ mới CHƯA có affiliate/referral** (Explore xác nhận). Cần build context affiliate trước khi migrate. |
| `test_*.json` | Dữ liệu test. Bỏ. |
| `*.txt`, `*.log`, `*.save`, `erl_crash.dump`, `backup.sql` | File log/backup/source cũ. Không phải dữ liệu cần migrate. |
| `download_tokens.json`, `banned_tele_ids.json` (rỗng), `blocked_sites_db.json` (rỗng), `keyword_rank_db.json` (rỗng) | Rỗng hoặc tạm thời. |

---

## Tóm tắt ưu tiên

| # | Phần | Nguồn | Đích | Độ khó | Trạng thái |
|---|---|---|---|---|---|
| 1 | **Users** | users_db.json (326) | `users` | Dễ | ✅ DONE — `priv/repo/seeds/webindex_migration.exs` |
| 2 | **Tier→Credit/Ví + Gói** | settings + level | `packages`+`wallets`+`ledger_entries` | TB | ✅ DONE — cùng seed trên |
| 3 | Lịch sử login | login_history_log.json (970) | `login_logs` | Dễ | ⬜ |
| 4 | Submit-index projects | project_submit_log + projects_db (87) | `index_projects`(+urls) | Dễ | ⬜ |
| 5 | Settings hệ thống | settings_db.json | `settings` | Dễ (lọc bớt) | ⬜ |
| 6 | Telegram templates | messages_config.json | `settings` | Dễ | ⬜ |
| 7 | Telegram config | telegram_config.json | settings/ENV | Dễ | ⬜ |
| 8 | Proxies/keys | backlink_proxy_keys.json + *_keys | `proxies`+`settings` | Dễ | ⬜ |
| — | Domain check | domain_projects_db.json | (chưa có feature) | Cần build trước | ❌ |
| — | Duplicate check | duplicate_projects_db.json | (chưa có feature) | Cần build trước | ❌ |
| — | Affiliate | affiliate_db.json | (chưa có context) | Cần build trước | ❌ |

**Khuyến nghị bắt đầu:** mục **1 (Users)** + **2 (Tier→Credit)** vì đó là thứ cho phép người dùng cũ đăng nhập và dùng được website mới. Các mục 3–8 là bổ sung.

> 👉 Bạn đánh dấu (✅) các mục muốn migrate, và với mục 2 cho tôi quy tắc đổi tier→credit/ngày-hết-hạn. Tôi sẽ viết script migrate (Elixir Mix task đọc JSON → insert qua Ecto).

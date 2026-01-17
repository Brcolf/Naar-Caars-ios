#!/usr/bin/env python3
"""
Script to add missing translations to Localizable.xcstrings
Adds Vietnamese (vi) and Korean (ko) translations to all strings
"""

import json
import sys

# Comprehensive translation dictionary
TRANSLATIONS = {
    # Common UI
    "Cancel": {"es": "Cancelar", "zh-Hans": "取消", "zh-Hant": "取消", "vi": "Hủy", "ko": "취소"},
    "Done": {"es": "Hecho", "zh-Hans": "完成", "zh-Hant": "完成", "vi": "Xong", "ko": "완료"},
    "OK": {"es": "Aceptar", "zh-Hans": "确定", "zh-Hant": "確定", "vi": "Đồng ý", "ko": "확인"},
    "Error": {"es": "Error", "zh-Hans": "错误", "zh-Hant": "錯誤", "vi": "Lỗi", "ko": "오류"},
    "Settings": {"es": "Configuración", "zh-Hans": "设置", "zh-Hant": "設定", "vi": "Cài đặt", "ko": "설정"},
    "Delete": {"es": "Eliminar", "zh-Hans": "删除", "zh-Hant": "刪除", "vi": "Xóa", "ko": "삭제"},
    "Save": {"es": "Guardar", "zh-Hans": "保存", "zh-Hant": "儲存", "vi": "Lưu", "ko": "저장"},
    "Edit": {"es": "Editar", "zh-Hans": "编辑", "zh-Hant": "編輯", "vi": "Chỉnh sửa", "ko": "편집"},
    "Post": {"es": "Publicar", "zh-Hans": "发布", "zh-Hant": "發布", "vi": "Đăng", "ko": "게시"},
    "Share": {"es": "Compartir", "zh-Hans": "分享", "zh-Hant": "分享", "vi": "Chia sẻ", "ko": "공유"},
    "Send": {"es": "Enviar", "zh-Hans": "发送", "zh-Hant": "發送", "vi": "Gửi", "ko": "보내기"},
    "Loading...": {"es": "Cargando...", "zh-Hans": "加载中...", "zh-Hant": "載入中...", "vi": "Đang tải...", "ko": "로딩 중..."},
    "Sign Out": {"es": "Cerrar sesión", "zh-Hans": "退出登录", "zh-Hant": "登出", "vi": "Đăng xuất", "ko": "로그아웃"},
    "My Profile": {"es": "Mi Perfil", "zh-Hans": "我的资料", "zh-Hant": "我的資料", "vi": "Hồ sơ của tôi", "ko": "내 프로필"},
    "Dashboard": {"es": "Panel", "zh-Hans": "仪表板", "zh-Hant": "儀表板", "vi": "Bảng điều khiển", "ko": "대시보드"},
    "Messages": {"es": "Mensajes", "zh-Hans": "消息", "zh-Hant": "訊息", "vi": "Tin nhắn", "ko": "메시지"},
    "Notifications": {"es": "Notificaciones", "zh-Hans": "通知", "zh-Hant": "通知", "vi": "Thông báo", "ko": "알림"},
    "Profile": {"es": "Perfil", "zh-Hans": "资料", "zh-Hant": "資料", "vi": "Hồ sơ", "ko": "프로필"},
    "Rides": {"es": "Viajes", "zh-Hans": "行程", "zh-Hant": "行程", "vi": "Đi xe", "ko": "승차"},
    "Favors": {"es": "Favores", "zh-Hans": "帮助", "zh-Hant": "幫助", "vi": "Giúp đỡ", "ko": "도움"},
    "Town Hall": {"es": "Ayuntamiento", "zh-Hans": "市政厅", "zh-Hant": "市政廳", "vi": "Tòa thị chính", "ko": "타운홀"},
    "Leaderboard": {"es": "Clasificación", "zh-Hans": "排行榜", "zh-Hant": "排行榜", "vi": "Bảng xếp hạng", "ko": "리더보드"},
    "Language": {"es": "Idioma", "zh-Hans": "语言", "zh-Hant": "語言", "vi": "Ngôn ngữ", "ko": "언어"},
    "General": {"es": "General", "zh-Hans": "通用", "zh-Hant": "一般", "vi": "Chung", "ko": "일반"},
    "Retry": {"es": "Reintentar", "zh-Hans": "重试", "zh-Hant": "重試", "vi": "Thử lại", "ko": "다시 시도"},
    "Try Again": {"es": "Intentar de nuevo", "zh-Hans": "再试一次", "zh-Hant": "再試一次", "vi": "Thử lại", "ko": "다시 시도"},
    "Next": {"es": "Siguiente", "zh-Hans": "下一步", "zh-Hant": "下一步", "vi": "Tiếp theo", "ko": "다음"},
    "Back to Profile": {"es": "Volver al Perfil", "zh-Hans": "返回资料", "zh-Hant": "返回資料", "vi": "Quay lại hồ sơ", "ko": "프로필로 돌아가기"},
    "Link": {"es": "Vincular", "zh-Hans": "关联", "zh-Hant": "關聯", "vi": "Liên kết", "ko": "연결"},
    "Copy": {"es": "Copiar", "zh-Hans": "复制", "zh-Hant": "複製", "vi": "Sao chép", "ko": "복사"},
    "Copied!": {"es": "¡Copiado!", "zh-Hans": "已复制！", "zh-Hant": "已複製！", "vi": "Đã sao chép!", "ko": "복사됨!"},
    "Show All": {"es": "Mostrar todo", "zh-Hans": "显示全部", "zh-Hant": "顯示全部", "vi": "Hiển thị tất cả", "ko": "모두 보기"},
    "Show Less": {"es": "Mostrar menos", "zh-Hans": "显示更少", "zh-Hant": "顯示更少", "vi": "Hiển thị ít hơn", "ko": "간략히 보기"},
    "View Details": {"es": "Ver detalles", "zh-Hans": "查看详情", "zh-Hant": "查看詳情", "vi": "Xem chi tiết", "ko": "세부 정보 보기"},
    "Filter": {"es": "Filtrar", "zh-Hans": "筛选", "zh-Hant": "篩選", "vi": "Lọc", "ko": "필터"},
    "View Mode": {"es": "Modo de vista", "zh-Hans": "查看模式", "zh-Hant": "查看模式", "vi": "Chế độ xem", "ko": "보기 모드"},
    "Recent": {"es": "Reciente", "zh-Hans": "最近", "zh-Hant": "最近", "vi": "Gần đây", "ko": "최근"},
    "Suggestions": {"es": "Sugerencias", "zh-Hans": "建议", "zh-Hant": "建議", "vi": "Gợi ý", "ko": "제안"},
    "No results found": {"es": "No se encontraron resultados", "zh-Hans": "未找到结果", "zh-Hant": "未找到結果", "vi": "Không tìm thấy kết quả", "ko": "결과 없음"},
    
    # Authentication
    "Sign Up": {"es": "Registrarse", "zh-Hans": "注册", "zh-Hant": "註冊", "vi": "Đăng ký", "ko": "가입"},
    "Sign In": {"es": "Iniciar sesión", "zh-Hans": "登录", "zh-Hant": "登入", "vi": "Đăng nhập", "ko": "로그인"},
    "Email": {"es": "Correo electrónico", "zh-Hans": "电子邮件", "zh-Hant": "電子郵件", "vi": "Email", "ko": "이메일"},
    "Password": {"es": "Contraseña", "zh-Hans": "密码", "zh-Hant": "密碼", "vi": "Mật khẩu", "ko": "비밀번호"},
    "Forgot Password?": {"es": "¿Olvidaste tu contraseña?", "zh-Hans": "忘记密码？", "zh-Hant": "忘記密碼？", "vi": "Quên mật khẩu?", "ko": "비밀번호를 잊으셨나요?"},
    "Don't have an account?": {"es": "¿No tienes una cuenta?", "zh-Hans": "还没有账户？", "zh-Hant": "還沒有帳戶？", "vi": "Chưa có tài khoản?", "ko": "계정이 없으신가요?"},
    "Create Account": {"es": "Crear cuenta", "zh-Hans": "创建账户", "zh-Hant": "建立帳戶", "vi": "Tạo tài khoản", "ko": "계정 만들기"},
    "Full Name": {"es": "Nombre completo", "zh-Hans": "全名", "zh-Hant": "全名", "vi": "Họ và tên", "ko": "전체 이름"},
    "Enter your name": {"es": "Ingresa tu nombre", "zh-Hans": "请输入您的姓名", "zh-Hant": "請輸入您的姓名", "vi": "Nhập tên của bạn", "ko": "이름을 입력하세요"},
    "Enter your email": {"es": "Ingresa tu correo electrónico", "zh-Hans": "请输入您的电子邮件", "zh-Hant": "請輸入您的電子郵件", "vi": "Nhập email của bạn", "ko": "이메일을 입력하세요"},
    "Enter your password": {"es": "Ingresa tu contraseña", "zh-Hans": "请输入您的密码", "zh-Hant": "請輸入您的密碼", "vi": "Nhập mật khẩu của bạn", "ko": "비밀번호를 입력하세요"},
    "Create a password": {"es": "Crea una contraseña", "zh-Hans": "创建密码", "zh-Hant": "建立密碼", "vi": "Tạo mật khẩu", "ko": "비밀번호 만들기"},
    "Join Naar's Cars": {"es": "Únete a Naar's Cars", "zh-Hans": "加入 Naar's Cars", "zh-Hant": "加入 Naar's Cars", "vi": "Tham gia Naar's Cars", "ko": "Naar's Cars에 가입"},
    "Enter your invite code to get started": {"es": "Ingresa tu código de invitación para comenzar", "zh-Hans": "输入您的邀请码以开始", "zh-Hant": "輸入您的邀請碼以開始", "vi": "Nhập mã mời để bắt đầu", "ko": "초대 코드를 입력하여 시작하세요"},
    "Invite Code": {"es": "Código de invitación", "zh-Hans": "邀请码", "zh-Hant": "邀請碼", "vi": "Mã mời", "ko": "초대 코드"},
    "Enter invite code": {"es": "Ingresa el código de invitación", "zh-Hans": "输入邀请码", "zh-Hant": "輸入邀請碼", "vi": "Nhập mã mời", "ko": "초대 코드 입력"},
    "Continue with Email": {"es": "Continuar con correo electrónico", "zh-Hans": "使用电子邮件继续", "zh-Hant": "使用電子郵件繼續", "vi": "Tiếp tục với email", "ko": "이메일로 계속"},
    "How would you like to sign up?": {"es": "¿Cómo te gustaría registrarte?", "zh-Hans": "您想如何注册？", "zh-Hant": "您想如何註冊？", "vi": "Bạn muốn đăng ký như thế nào?", "ko": "가입 방법을 선택하세요"},
    "Create Your Account": {"es": "Crea tu cuenta", "zh-Hans": "创建您的账户", "zh-Hant": "建立您的帳戶", "vi": "Tạo tài khoản của bạn", "ko": "계정 만들기"},
    "or": {"es": "o", "zh-Hans": "或", "zh-Hant": "或", "vi": "hoặc", "ko": "또는"},
    "Your Account is Pending Approval": {"es": "Tu cuenta está pendiente de aprobación", "zh-Hans": "您的账户待审核", "zh-Hant": "您的帳戶待審核", "vi": "Tài khoản của bạn đang chờ phê duyệt", "ko": "계정 승인 대기 중"},
    "Your account is pending approval from an administrator. You'll be notified once your account has been approved.": {"es": "Tu cuenta está pendiente de aprobación de un administrador. Se te notificará una vez que tu cuenta haya sido aprobada.", "zh-Hans": "您的账户正在等待管理员审核。账户获得批准后，您将收到通知。", "zh-Hant": "您的帳戶正在等待管理員審核。帳戶獲得批准後，您將收到通知。", "vi": "Tài khoản của bạn đang chờ quản trị viên phê duyệt. Bạn sẽ được thông báo khi tài khoản được phê duyệt.", "ko": "계정이 관리자의 승인을 기다리고 있습니다. 승인되면 알림을 받게 됩니다."},
    "Authentication Failed": {"es": "Autenticación fallida", "zh-Hans": "认证失败", "zh-Hant": "認證失敗", "vi": "Xác thực thất bại", "ko": "인증 실패"},
    "Not Signed In": {"es": "No has iniciado sesión", "zh-Hans": "未登录", "zh-Hant": "未登入", "vi": "Chưa đăng nhập", "ko": "로그인되지 않음"},
    "Please sign in to view your profile.": {"es": "Por favor inicia sesión para ver tu perfil.", "zh-Hans": "请登录以查看您的资料。", "zh-Hant": "請登入以查看您的資料。", "vi": "Vui lòng đăng nhập để xem hồ sơ của bạn.", "ko": "프로필을 보려면 로그인하세요."},
    "Reset Password": {"es": "Restablecer contraseña", "zh-Hans": "重置密码", "zh-Hant": "重設密碼", "vi": "Đặt lại mật khẩu", "ko": "비밀번호 재설정"},
    "Enter your email address and we'll send you a password reset link.": {"es": "Ingresa tu dirección de correo electrónico y te enviaremos un enlace para restablecer tu contraseña.", "zh-Hans": "请输入您的电子邮件地址，我们将向您发送密码重置链接。", "zh-Hant": "請輸入您的電子郵件地址，我們將向您發送密碼重設連結。", "vi": "Nhập địa chỉ email của bạn và chúng tôi sẽ gửi cho bạn liên kết đặt lại mật khẩu.", "ko": "이메일 주소를 입력하시면 비밀번호 재설정 링크를 보내드립니다."},
    "If an account exists with this email, you'll receive a password reset link.": {"es": "Si existe una cuenta con este correo electrónico, recibirás un enlace para restablecer tu contraseña.", "zh-Hans": "如果此电子邮件存在账户，您将收到密码重置链接。", "zh-Hant": "如果此電子郵件存在帳戶，您將收到密碼重設連結。", "vi": "Nếu có tài khoản với email này, bạn sẽ nhận được liên kết đặt lại mật khẩu.", "ko": "이 이메일로 계정이 있으면 비밀번호 재설정 링크를 받게 됩니다."},
    "Send Reset Link": {"es": "Enviar enlace de restablecimiento", "zh-Hans": "发送重置链接", "zh-Hant": "發送重設連結", "vi": "Gửi liên kết đặt lại", "ko": "재설정 링크 보내기"},
    
    # Profile
    "Change Photo": {"es": "Cambiar foto", "zh-Hans": "更换照片", "zh-Hant": "更換照片", "vi": "Đổi ảnh", "ko": "사진 변경"},
    "Add Photo": {"es": "Agregar foto", "zh-Hans": "添加照片", "zh-Hant": "新增照片", "vi": "Thêm ảnh", "ko": "사진 추가"},
    "Edit Profile": {"es": "Editar perfil", "zh-Hans": "编辑资料", "zh-Hant": "編輯資料", "vi": "Chỉnh sửa hồ sơ", "ko": "프로필 편집"},
    "Name": {"es": "Nombre", "zh-Hans": "姓名", "zh-Hant": "姓名", "vi": "Tên", "ko": "이름"},
    "Car (Optional)": {"es": "Coche (opcional)", "zh-Hans": "汽车（可选）", "zh-Hant": "汽車（選填）", "vi": "Xe (tùy chọn)", "ko": "차량 (선택사항)"},
    "Car Description": {"es": "Descripción del coche", "zh-Hans": "汽车描述", "zh-Hant": "汽車描述", "vi": "Mô tả xe", "ko": "차량 설명"},
    "e.g., 2020 Toyota Camry": {"es": "ej., Toyota Camry 2020", "zh-Hans": "例如：2020 丰田凯美瑞", "zh-Hant": "例如：2020 豐田凱美瑞", "vi": "vd: Toyota Camry 2020", "ko": "예: 2020년 토요타 캠리"},
    "Phone Number": {"es": "Número de teléfono", "zh-Hans": "电话号码", "zh-Hant": "電話號碼", "vi": "Số điện thoại", "ko": "전화번호"},
    "Phone Number Required": {"es": "Número de teléfono requerido", "zh-Hans": "需要电话号码", "zh-Hant": "需要電話號碼", "vi": "Cần số điện thoại", "ko": "전화번호 필요"},
    "Phone Required": {"es": "Teléfono requerido", "zh-Hans": "需要电话", "zh-Hant": "需要電話", "vi": "Cần điện thoại", "ko": "전화번호 필요"},
    "Phone Number Visibility": {"es": "Visibilidad del número de teléfono", "zh-Hans": "电话号码可见性", "zh-Hant": "電話號碼可見性", "vi": "Hiển thị số điện thoại", "ko": "전화번호 공개 여부"},
    "Your number will be visible to other community members.": {"es": "Tu número será visible para otros miembros de la comunidad.", "zh-Hans": "您的号码将对其他社区成员可见。", "zh-Hant": "您的號碼將對其他社區成員可見。", "vi": "Số của bạn sẽ hiển thị cho các thành viên khác trong cộng đồng.", "ko": "번호가 다른 커뮤니티 구성원에게 표시됩니다."},
    "Your phone number will be visible to community members for ride coordination.": {"es": "Tu número de teléfono será visible para los miembros de la comunidad para coordinar viajes.", "zh-Hans": "您的电话号码将对社区成员可见，以便协调行程。", "zh-Hant": "您的電話號碼將對社區成員可見，以便協調行程。", "vi": "Số điện thoại của bạn sẽ hiển thị cho các thành viên trong cộng đồng để phối hợp đi xe.", "ko": "승차 조정을 위해 전화번호가 커뮤니티 구성원에게 표시됩니다."},
    "Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?": {"es": "Tu número de teléfono será visible para otros miembros de Naar's Cars para coordinar viajes y favores. ¿Continuar?", "zh-Hans": "您的电话号码将对其他 Naar's Cars 成员可见，以便协调行程和帮助。继续吗？", "zh-Hant": "您的電話號碼將對其他 Naar's Cars 成員可見，以便協調行程和幫助。繼續嗎？", "vi": "Số điện thoại của bạn sẽ hiển thị cho các thành viên Naar's Cars khác để phối hợp đi xe và giúp đỡ. Tiếp tục?", "ko": "승차 및 도움 조정을 위해 전화번호가 다른 Naar's Cars 구성원에게 표시됩니다. 계속하시겠습니까?"},
    "Yes, Save Number": {"es": "Sí, guardar número", "zh-Hans": "是，保存号码", "zh-Hant": "是，儲存號碼", "vi": "Có, lưu số", "ko": "예, 번호 저장"},
    "Reveal Number": {"es": "Revelar número", "zh-Hans": "显示号码", "zh-Hant": "顯示號碼", "vi": "Hiển thị số", "ko": "번호 표시"},
    "You can change this later in Settings": {"es": "Puedes cambiar esto más tarde en Configuración", "zh-Hans": "您稍后可以在设置中更改", "zh-Hant": "您稍後可以在設定中更改", "vi": "Bạn có thể thay đổi điều này sau trong Cài đặt", "ko": "나중에 설정에서 변경할 수 있습니다"},
    "Photo Access Required": {"es": "Se requiere acceso a fotos", "zh-Hans": "需要照片访问权限", "zh-Hant": "需要照片存取權限", "vi": "Cần quyền truy cập ảnh", "ko": "사진 접근 권한 필요"},
    "To change your profile photo, please enable photo access in Settings.": {"es": "Para cambiar tu foto de perfil, por favor habilita el acceso a fotos en Configuración.", "zh-Hans": "要更改您的资料照片，请在设置中启用照片访问权限。", "zh-Hant": "要更改您的資料照片，請在設定中啟用照片存取權限。", "vi": "Để thay đổi ảnh hồ sơ, vui lòng bật quyền truy cập ảnh trong Cài đặt.", "ko": "프로필 사진을 변경하려면 설정에서 사진 접근 권한을 활성화하세요."},
    "Remove Image": {"es": "Eliminar imagen", "zh-Hans": "删除图片", "zh-Hant": "刪除圖片", "vi": "Xóa ảnh", "ko": "이미지 제거"},
    "Uploading avatar...": {"es": "Subiendo avatar...", "zh-Hans": "上传头像中...", "zh-Hant": "上傳頭像中...", "vi": "Đang tải ảnh đại diện...", "ko": "아바타 업로드 중..."},
    "Saving...": {"es": "Guardando...", "zh-Hans": "保存中...", "zh-Hant": "儲存中...", "vi": "Đang lưu...", "ko": "저장 중..."},
    "Delete Account": {"es": "Eliminar cuenta", "zh-Hans": "删除账户", "zh-Hant": "刪除帳戶", "vi": "Xóa tài khoản", "ko": "계정 삭제"},
    "Are you absolutely sure? This will permanently delete your account and all associated data. This action cannot be undone.": {"es": "¿Estás absolutamente seguro? Esto eliminará permanentemente tu cuenta y todos los datos asociados. Esta acción no se puede deshacer.", "zh-Hans": "您确定吗？这将永久删除您的账户和所有相关数据。此操作无法撤销。", "zh-Hant": "您確定嗎？這將永久刪除您的帳戶和所有相關資料。此操作無法撤銷。", "vi": "Bạn có chắc chắn không? Điều này sẽ xóa vĩnh viễn tài khoản và tất cả dữ liệu liên quan. Hành động này không thể hoàn tác.", "ko": "정말로 확실하신가요? 계정과 모든 관련 데이터가 영구적으로 삭제됩니다. 이 작업은 취소할 수 없습니다."},
    "This action cannot be undone. You will lose all information associated with your account, including any content you have generated such as rides, reviews, and posts.": {"es": "Esta acción no se puede deshacer. Perderás toda la información asociada con tu cuenta, incluyendo cualquier contenido que hayas generado como viajes, reseñas y publicaciones.", "zh-Hans": "此操作无法撤销。您将丢失与账户关联的所有信息，包括您生成的所有内容，如行程、评价和帖子。", "zh-Hant": "此操作無法撤銷。您將遺失與帳戶關聯的所有資訊，包括您產生的所有內容，如行程、評價和帖子。", "vi": "Hành động này không thể hoàn tác. Bạn sẽ mất tất cả thông tin liên quan đến tài khoản, bao gồm mọi nội dung bạn đã tạo như đi xe, đánh giá và bài đăng.", "ko": "이 작업은 취소할 수 없습니다. 계정과 연결된 모든 정보(승차, 리뷰, 게시물 등 생성한 모든 콘텐츠 포함)가 손실됩니다."},
    "Confirm Account Deletion": {"es": "Confirmar eliminación de cuenta", "zh-Hans": "确认删除账户", "zh-Hant": "確認刪除帳戶", "vi": "Xác nhận xóa tài khoản", "ko": "계정 삭제 확인"},
    "Deleting account...": {"es": "Eliminando cuenta...", "zh-Hans": "正在删除账户...", "zh-Hant": "正在刪除帳戶...", "vi": "Đang xóa tài khoản...", "ko": "계정 삭제 중..."},
    "Your profile will appear here": {"es": "Tu perfil aparecerá aquí", "zh-Hans": "您的资料将显示在这里", "zh-Hant": "您的資料將顯示在這裡", "vi": "Hồ sơ của bạn sẽ hiển thị ở đây", "ko": "프로필이 여기에 표시됩니다"},
    "Stats": {"es": "Estadísticas", "zh-Hans": "统计", "zh-Hant": "統計", "vi": "Thống kê", "ko": "통계"},
    "Reviews": {"es": "Reseñas", "zh-Hans": "评价", "zh-Hant": "評價", "vi": "Đánh giá", "ko": "리뷰"},
    "Rating": {"es": "Calificación", "zh-Hans": "评分", "zh-Hant": "評分", "vi": "Đánh giá", "ko": "평점"},
    "No Rating": {"es": "Sin calificación", "zh-Hans": "无评分", "zh-Hant": "無評分", "vi": "Không có đánh giá", "ko": "평점 없음"},
    "fulfilled": {"es": "completados", "zh-Hans": "已完成", "zh-Hant": "已完成", "vi": "đã hoàn thành", "ko": "완료됨"},
    "Fulfilled": {"es": "Completado", "zh-Hans": "已完成", "zh-Hant": "已完成", "vi": "Đã hoàn thành", "ko": "완료됨"},
    "Available": {"es": "Disponible", "zh-Hans": "可用", "zh-Hant": "可用", "vi": "Có sẵn", "ko": "사용 가능"},
    
    # Invites
    "🎟️ Invite Codes": {"es": "🎟️ Códigos de invitación", "zh-Hans": "🎟️ 邀请码", "zh-Hant": "🎟️ 邀請碼", "vi": "🎟️ Mã mời", "ko": "🎟️ 초대 코드"},
    "Invite Codes": {"es": "Códigos de invitación", "zh-Hans": "邀请码", "zh-Hant": "邀請碼", "vi": "Mã mời", "ko": "초대 코드"},
    "Invite a Neighbor": {"es": "Invitar a un vecino", "zh-Hans": "邀请邻居", "zh-Hant": "邀請鄰居", "vi": "Mời hàng xóm", "ko": "이웃 초대"},
    "Generate Invite Code": {"es": "Generar código de invitación", "zh-Hans": "生成邀请码", "zh-Hant": "產生邀請碼", "vi": "Tạo mã mời", "ko": "초대 코드 생성"},
    "Create Invite": {"es": "Crear invitación", "zh-Hans": "创建邀请", "zh-Hant": "建立邀請", "vi": "Tạo lời mời", "ko": "초대 만들기"},
    "Create a code to invite new members": {"es": "Crea un código para invitar nuevos miembros", "zh-Hans": "创建代码以邀请新成员", "zh-Hant": "建立代碼以邀請新成員", "vi": "Tạo mã để mời thành viên mới", "ko": "새 구성원 초대 코드 만들기"},
    "Who are you inviting and why?": {"es": "¿A quién estás invitando y por qué?", "zh-Hans": "您要邀请谁？为什么？", "zh-Hant": "您要邀請誰？為什麼？", "vi": "Bạn đang mời ai và tại sao?", "ko": "누구를 초대하시나요? 이유는 무엇인가요?"},
    "Tell us about who you're inviting": {"es": "Cuéntanos sobre a quién estás invitando", "zh-Hans": "告诉我们您要邀请的人", "zh-Hant": "告訴我們您要邀請的人", "vi": "Cho chúng tôi biết về người bạn đang mời", "ko": "초대할 사람에 대해 알려주세요"},
    "Invitation Statement": {"es": "Declaración de invitación", "zh-Hans": "邀请说明", "zh-Hant": "邀請說明", "vi": "Lời mời", "ko": "초대 문구"},
    "No invitation statement provided": {"es": "No se proporcionó declaración de invitación", "zh-Hans": "未提供邀请说明", "zh-Hant": "未提供邀請說明", "vi": "Không có lời mời", "ko": "초대 문구 없음"},
    "Regular Invite": {"es": "Invitación regular", "zh-Hans": "常规邀请", "zh-Hant": "常規邀請", "vi": "Lời mời thường", "ko": "일반 초대"},
    "Single-use code with invitation statement": {"es": "Código de un solo uso con declaración de invitación", "zh-Hans": "带邀请说明的单次使用代码", "zh-Hant": "帶邀請說明的單次使用代碼", "vi": "Mã dùng một lần với lời mời", "ko": "초대 문구가 있는 일회용 코드"},
    "Bulk Invite": {"es": "Invitación masiva", "zh-Hans": "批量邀请", "zh-Hant": "批量邀請", "vi": "Lời mời hàng loạt", "ko": "일괄 초대"},
    "Bulk Invite Code": {"es": "Código de invitación masiva", "zh-Hans": "批量邀请码", "zh-Hant": "批量邀請碼", "vi": "Mã mời hàng loạt", "ko": "일괄 초대 코드"},
    "Multi-use code (expires in 48 hours)": {"es": "Código de múltiple uso (expira en 48 horas)", "zh-Hans": "多次使用代码（48小时后过期）", "zh-Hant": "多次使用代碼（48小時後過期）", "vi": "Mã dùng nhiều lần (hết hạn sau 48 giờ)", "ko": "다회용 코드 (48시간 후 만료)"},
    "This code can be used by multiple people and will expire in 48 hours": {"es": "Este código puede ser usado por múltiples personas y expirará en 48 horas", "zh-Hans": "此代码可供多人使用，将在48小时后过期", "zh-Hant": "此代碼可供多人使用，將在48小時後過期", "vi": "Mã này có thể được nhiều người sử dụng và sẽ hết hạn sau 48 giờ", "ko": "이 코드는 여러 사람이 사용할 수 있으며 48시간 후 만료됩니다"},
    "Invite Code Generated!": {"es": "¡Código de invitación generado!", "zh-Hans": "邀请码已生成！", "zh-Hant": "邀請碼已產生！", "vi": "Mã mời đã được tạo!", "ko": "초대 코드 생성됨!"},
    "Generated Code": {"es": "Código generado", "zh-Hans": "已生成的代码", "zh-Hant": "已產生的代碼", "vi": "Mã đã tạo", "ko": "생성된 코드"},
    "Your Invite Code": {"es": "Tu código de invitación", "zh-Hans": "您的邀请码", "zh-Hant": "您的邀請碼", "vi": "Mã mời của bạn", "ko": "초대 코드"},
    "Share this code with someone you'd like to invite": {"es": "Comparte este código con alguien que te gustaría invitar", "zh-Hans": "与您想邀请的人分享此代码", "zh-Hant": "與您想邀請的人分享此代碼", "vi": "Chia sẻ mã này với người bạn muốn mời", "ko": "초대하고 싶은 사람과 이 코드를 공유하세요"},
    "Used": {"es": "Usado", "zh-Hans": "已使用", "zh-Hant": "已使用", "vi": "Đã sử dụng", "ko": "사용됨"},
    "Used by: %@": {"es": "Usado por: %@", "zh-Hans": "使用者：%@", "zh-Hant": "使用者：%@", "vi": "Được sử dụng bởi: %@", "ko": "사용자: %@"},
    "Expires: %@ at %@": {"es": "Expira: %@ a las %@", "zh-Hans": "过期：%@ %@", "zh-Hant": "過期：%@ %@", "vi": "Hết hạn: %@ lúc %@", "ko": "만료: %@ %@"},
    "Invited By": {"es": "Invitado por", "zh-Hans": "邀请人", "zh-Hant": "邀請人", "vi": "Được mời bởi", "ko": "초대한 사람"},
    "Invited by: %@": {"es": "Invitado por: %@", "zh-Hans": "邀请人：%@", "zh-Hant": "邀請人：%@", "vi": "Được mời bởi: %@", "ko": "초대한 사람: %@"},
    "Invited by: Unknown": {"es": "Invitado por: Desconocido", "zh-Hans": "邀请人：未知", "zh-Hant": "邀請人：未知", "vi": "Được mời bởi: Không xác định", "ko": "초대한 사람: 알 수 없음"},
    "Invite Information": {"es": "Información de invitación", "zh-Hans": "邀请信息", "zh-Hant": "邀請資訊", "vi": "Thông tin mời", "ko": "초대 정보"},
    "Loading invite details...": {"es": "Cargando detalles de invitación...", "zh-Hans": "加载邀请详情中...", "zh-Hant": "載入邀請詳情中...", "vi": "Đang tải chi tiết lời mời...", "ko": "초대 세부 정보 로딩 중..."},
    
    # Rides
    "Ride Requests": {"es": "Solicitudes de viaje", "zh-Hans": "行程请求", "zh-Hant": "行程請求", "vi": "Yêu cầu đi xe", "ko": "승차 요청"},
    "Create Ride Request": {"es": "Crear solicitud de viaje", "zh-Hans": "创建行程请求", "zh-Hant": "建立行程請求", "vi": "Tạo yêu cầu đi xe", "ko": "승차 요청 만들기"},
    "Edit Ride Request": {"es": "Editar solicitud de viaje", "zh-Hans": "编辑行程请求", "zh-Hant": "編輯行程請求", "vi": "Chỉnh sửa yêu cầu đi xe", "ko": "승차 요청 편집"},
    "Delete Ride": {"es": "Eliminar viaje", "zh-Hans": "删除行程", "zh-Hant": "刪除行程", "vi": "Xóa đi xe", "ko": "승차 삭제"},
    "Are you sure you want to delete this ride request? This action cannot be undone.": {"es": "¿Estás seguro de que quieres eliminar esta solicitud de viaje? Esta acción no se puede deshacer.", "zh-Hans": "您确定要删除此行程请求吗？此操作无法撤销。", "zh-Hant": "您確定要刪除此行程請求嗎？此操作無法撤銷。", "vi": "Bạn có chắc muốn xóa yêu cầu đi xe này không? Hành động này không thể hoàn tác.", "ko": "이 승차 요청을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다."},
    "Ride Details": {"es": "Detalles del viaje", "zh-Hans": "行程详情", "zh-Hant": "行程詳情", "vi": "Chi tiết đi xe", "ko": "승차 세부 정보"},
    "Date & Time": {"es": "Fecha y hora", "zh-Hans": "日期和时间", "zh-Hant": "日期和時間", "vi": "Ngày và giờ", "ko": "날짜 및 시간"},
    "Date": {"es": "Fecha", "zh-Hans": "日期", "zh-Hant": "日期", "vi": "Ngày", "ko": "날짜"},
    "Time": {"es": "Hora", "zh-Hans": "时间", "zh-Hant": "時間", "vi": "Giờ", "ko": "시간"},
    "Time (optional)": {"es": "Hora (opcional)", "zh-Hans": "时间（可选）", "zh-Hant": "時間（選填）", "vi": "Giờ (tùy chọn)", "ko": "시간 (선택사항)"},
    "HH:mm": {"es": "HH:mm", "zh-Hans": "时:分", "zh-Hant": "時:分", "vi": "HH:mm", "ko": "시:분"},
    "Route": {"es": "Ruta", "zh-Hans": "路线", "zh-Hant": "路線", "vi": "Tuyến đường", "ko": "경로"},
    "Pickup Location": {"es": "Ubicación de recogida", "zh-Hans": "上车地点", "zh-Hant": "上車地點", "vi": "Điểm đón", "ko": "탑승 장소"},
    "Destination": {"es": "Destino", "zh-Hans": "目的地", "zh-Hant": "目的地", "vi": "Điểm đến", "ko": "목적지"},
    "Details": {"es": "Detalles", "zh-Hans": "详情", "zh-Hant": "詳情", "vi": "Chi tiết", "ko": "세부 정보"},
    "Seats: %lld": {"es": "Asientos: %lld", "zh-Hans": "座位：%lld", "zh-Hant": "座位：%lld", "vi": "Ghế: %lld", "ko": "좌석: %lld"},
    "Notes": {"es": "Notas", "zh-Hans": "备注", "zh-Hant": "備註", "vi": "Ghi chú", "ko": "메모"},
    "Notes (optional)": {"es": "Notas (opcional)", "zh-Hans": "备注（可选）", "zh-Hant": "備註（選填）", "vi": "Ghi chú (tùy chọn)", "ko": "메모 (선택사항)"},
    "Gift/Compensation": {"es": "Regalo/Compensación", "zh-Hans": "礼物/补偿", "zh-Hant": "禮物/補償", "vi": "Quà tặng/Bồi thường", "ko": "선물/보상"},
    "Gift/Compensation (optional)": {"es": "Regalo/Compensación (opcional)", "zh-Hans": "礼物/补偿（可选）", "zh-Hant": "禮物/補償（選填）", "vi": "Quà tặng/Bồi thường (tùy chọn)", "ko": "선물/보상 (선택사항)"},
    "Claim Request": {"es": "Reclamar solicitud", "zh-Hans": "认领请求", "zh-Hant": "認領請求", "vi": "Nhận yêu cầu", "ko": "요청 수락"},
    "Claim This %@?": {"es": "¿Reclamar este %@?", "zh-Hans": "认领此 %@？", "zh-Hant": "認領此 %@？", "vi": "Nhận %@ này?", "ko": "이 %@을(를) 수락하시겠습니까?"},
    "You're volunteering to help with:": {"es": "Te estás ofreciendo a ayudar con:", "zh-Hans": "您自愿帮助：", "zh-Hant": "您自願幫助：", "vi": "Bạn đang tình nguyện giúp đỡ:", "ko": "도움을 제공하시겠습니까:"},
    "A conversation will be created so you can coordinate with the poster.": {"es": "Se creará una conversación para que puedas coordinar con el publicador.", "zh-Hans": "将创建对话，以便您与发布者协调。", "zh-Hant": "將建立對話，以便您與發布者協調。", "vi": "Một cuộc trò chuyện sẽ được tạo để bạn có thể phối hợp với người đăng.", "ko": "게시자와 조정할 수 있도록 대화가 생성됩니다."},
    "To claim requests, you need to add a phone number so the poster can coordinate with you.": {"es": "Para reclamar solicitudes, necesitas agregar un número de teléfono para que el publicador pueda coordinar contigo.", "zh-Hans": "要认领请求，您需要添加电话号码，以便发布者可以与您协调。", "zh-Hant": "要認領請求，您需要新增電話號碼，以便發布者可以與您協調。", "vi": "Để nhận yêu cầu, bạn cần thêm số điện thoại để người đăng có thể phối hợp với bạn.", "ko": "요청을 수락하려면 게시자가 조정할 수 있도록 전화번호를 추가해야 합니다."},
    "Complete Request": {"es": "Completar solicitud", "zh-Hans": "完成请求", "zh-Hant": "完成請求", "vi": "Hoàn thành yêu cầu", "ko": "요청 완료"},
    "Mark as Completed?": {"es": "¿Marcar como completado?", "zh-Hans": "标记为已完成？", "zh-Hant": "標記為已完成？", "vi": "Đánh dấu là đã hoàn thành?", "ko": "완료로 표시하시겠습니까?"},
    "You're marking this as complete:": {"es": "Estás marcando esto como completado:", "zh-Hans": "您将此标记为已完成：", "zh-Hant": "您將此標記為已完成：", "vi": "Bạn đang đánh dấu điều này là hoàn thành:", "ko": "다음 항목을 완료로 표시합니다:"},
    "After marking complete, you'll be prompted to leave a review for your helper.": {"es": "Después de marcar como completado, se te pedirá que dejes una reseña para tu ayudante.", "zh-Hans": "标记完成后，系统将提示您为帮助者留下评价。", "zh-Hant": "標記完成後，系統將提示您為幫助者留下評價。", "vi": "Sau khi đánh dấu hoàn thành, bạn sẽ được nhắc để lại đánh giá cho người giúp đỡ.", "ko": "완료로 표시한 후 도움을 준 사람에 대한 리뷰를 남기라는 메시지가 표시됩니다."},
    "Unclaim Request": {"es": "Desreclamar solicitud", "zh-Hans": "取消认领", "zh-Hant": "取消認領", "vi": "Hủy nhận yêu cầu", "ko": "요청 취소"},
    "Unclaim This %@?": {"es": "¿Desreclamar este %@?", "zh-Hans": "取消认领此 %@？", "zh-Hant": "取消認領此 %@？", "vi": "Hủy nhận %@ này?", "ko": "이 %@을(를) 취소하시겠습니까?"},
    "You're about to unclaim:": {"es": "Estás a punto de desreclamar:", "zh-Hans": "您即将取消认领：", "zh-Hant": "您即將取消認領：", "vi": "Bạn sắp hủy nhận:", "ko": "다음 항목의 수락을 취소합니다:"},
    "The request will return to open status and the poster will be notified.": {"es": "La solicitud volverá al estado abierto y se notificará al publicador.", "zh-Hans": "请求将返回开放状态，发布者将收到通知。", "zh-Hant": "請求將返回開放狀態，發布者將收到通知。", "vi": "Yêu cầu sẽ trở lại trạng thái mở và người đăng sẽ được thông báo.", "ko": "요청이 열림 상태로 돌아가고 게시자에게 알림이 전송됩니다."},
    
    # Favors
    "Favor Requests": {"es": "Solicitudes de favor", "zh-Hans": "帮助请求", "zh-Hant": "幫助請求", "vi": "Yêu cầu giúp đỡ", "ko": "도움 요청"},
    "Create Favor Request": {"es": "Crear solicitud de favor", "zh-Hans": "创建帮助请求", "zh-Hant": "建立幫助請求", "vi": "Tạo yêu cầu giúp đỡ", "ko": "도움 요청 만들기"},
    "Edit Favor Request": {"es": "Editar solicitud de favor", "zh-Hans": "编辑帮助请求", "zh-Hant": "編輯幫助請求", "vi": "Chỉnh sửa yêu cầu giúp đỡ", "ko": "도움 요청 편집"},
    "Delete Favor": {"es": "Eliminar favor", "zh-Hans": "删除帮助", "zh-Hant": "刪除幫助", "vi": "Xóa giúp đỡ", "ko": "도움 삭제"},
    "Are you sure you want to delete this favor request? This action cannot be undone.": {"es": "¿Estás seguro de que quieres eliminar esta solicitud de favor? Esta acción no se puede deshacer.", "zh-Hans": "您确定要删除此帮助请求吗？此操作无法撤销。", "zh-Hant": "您確定要刪除此幫助請求嗎？此操作無法撤銷。", "vi": "Bạn có chắc muốn xóa yêu cầu giúp đỡ này không? Hành động này không thể hoàn tác.", "ko": "이 도움 요청을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다."},
    "Favor Details": {"es": "Detalles del favor", "zh-Hans": "帮助详情", "zh-Hant": "幫助詳情", "vi": "Chi tiết giúp đỡ", "ko": "도움 세부 정보"},
    "Title & Description": {"es": "Título y descripción", "zh-Hans": "标题和描述", "zh-Hant": "標題和描述", "vi": "Tiêu đề và mô tả", "ko": "제목 및 설명"},
    "Title": {"es": "Título", "zh-Hans": "标题", "zh-Hant": "標題", "vi": "Tiêu đề", "ko": "제목"},
    "Description (optional)": {"es": "Descripción (opcional)", "zh-Hans": "描述（可选）", "zh-Hant": "描述（選填）", "vi": "Mô tả (tùy chọn)", "ko": "설명 (선택사항)"},
    "Location & Duration": {"es": "Ubicación y duración", "zh-Hans": "位置和时长", "zh-Hant": "位置和時長", "vi": "Vị trí và thời lượng", "ko": "위치 및 소요 시간"},
    "Location": {"es": "Ubicación", "zh-Hans": "位置", "zh-Hant": "位置", "vi": "Vị trí", "ko": "위치"},
    "Duration": {"es": "Duración", "zh-Hans": "时长", "zh-Hant": "時長", "vi": "Thời lượng", "ko": "소요 시간"},
    "Requirements": {"es": "Requisitos", "zh-Hans": "要求", "zh-Hant": "要求", "vi": "Yêu cầu", "ko": "요구사항"},
    "Requirements (optional)": {"es": "Requisitos (opcional)", "zh-Hans": "要求（可选）", "zh-Hant": "要求（選填）", "vi": "Yêu cầu (tùy chọn)", "ko": "요구사항 (선택사항)"},
    
    # Messages
    "Chat": {"es": "Chat", "zh-Hans": "聊天", "zh-Hant": "聊天", "vi": "Trò chuyện", "ko": "채팅"},
    "No messages yet": {"es": "Aún no hay mensajes", "zh-Hans": "暂无消息", "zh-Hant": "暫無訊息", "vi": "Chưa có tin nhắn", "ko": "메시지 없음"},
    "Your conversations will appear here": {"es": "Tus conversaciones aparecerán aquí", "zh-Hans": "您的对话将显示在这里", "zh-Hant": "您的對話將顯示在這裡", "vi": "Cuộc trò chuyện của bạn sẽ hiển thị ở đây", "ko": "대화가 여기에 표시됩니다"},
    "Type a message...": {"es": "Escribe un mensaje...", "zh-Hans": "输入消息...", "zh-Hant": "輸入訊息...", "vi": "Nhập tin nhắn...", "ko": "메시지 입력..."},
    "Send Message": {"es": "Enviar mensaje", "zh-Hans": "发送消息", "zh-Hant": "發送訊息", "vi": "Gửi tin nhắn", "ko": "메시지 보내기"},
    "Add Participants": {"es": "Agregar participantes", "zh-Hans": "添加参与者", "zh-Hant": "新增參與者", "vi": "Thêm người tham gia", "ko": "참가자 추가"},
    "Already added": {"es": "Ya agregado", "zh-Hans": "已添加", "zh-Hant": "已新增", "vi": "Đã thêm", "ko": "이미 추가됨"},
    "Message All Participants": {"es": "Mensaje a todos los participantes", "zh-Hans": "向所有参与者发送消息", "zh-Hant": "向所有參與者發送訊息", "vi": "Gửi tin nhắn cho tất cả người tham gia", "ko": "모든 참가자에게 메시지"},
    "Select Users": {"es": "Seleccionar usuarios", "zh-Hans": "选择用户", "zh-Hant": "選擇使用者", "vi": "Chọn người dùng", "ko": "사용자 선택"},
    
    # Notifications
    "Mark All Read": {"es": "Marcar todo como leído", "zh-Hans": "全部标记为已读", "zh-Hant": "全部標記為已讀", "vi": "Đánh dấu tất cả là đã đọc", "ko": "모두 읽음으로 표시"},
    "Announcement": {"es": "Anuncio", "zh-Hans": "公告", "zh-Hant": "公告", "vi": "Thông báo", "ko": "공지"},
    
    # Town Hall
    "New Post": {"es": "Nueva publicación", "zh-Hans": "新帖子", "zh-Hant": "新帖子", "vi": "Bài đăng mới", "ko": "새 게시물"},
    "What's on your mind?": {"es": "¿En qué estás pensando?", "zh-Hans": "您在想什么？", "zh-Hant": "您在想什麼？", "vi": "Bạn đang nghĩ gì?", "ko": "무엇을 생각하고 계신가요?"},
    "Share with the Community": {"es": "Compartir con la comunidad", "zh-Hans": "与社区分享", "zh-Hant": "與社區分享", "vi": "Chia sẻ với cộng đồng", "ko": "커뮤니티와 공유"},
    "Delete Post": {"es": "Eliminar publicación", "zh-Hans": "删除帖子", "zh-Hant": "刪除帖子", "vi": "Xóa bài đăng", "ko": "게시물 삭제"},
    "Are you sure you want to delete this post? This action cannot be undone.": {"es": "¿Estás seguro de que quieres eliminar esta publicación? Esta acción no se puede deshacer.", "zh-Hans": "您确定要删除此帖子吗？此操作无法撤销。", "zh-Hant": "您確定要刪除此帖子嗎？此操作無法撤銷。", "vi": "Bạn có chắc muốn xóa bài đăng này không? Hành động này không thể hoàn tác.", "ko": "이 게시물을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다."},
    "Image": {"es": "Imagen", "zh-Hans": "图片", "zh-Hant": "圖片", "vi": "Hình ảnh", "ko": "이미지"},
    "Image (Optional)": {"es": "Imagen (opcional)", "zh-Hans": "图片（可选）", "zh-Hant": "圖片（選填）", "vi": "Hình ảnh (tùy chọn)", "ko": "이미지 (선택사항)"},
    "Questions & Answers": {"es": "Preguntas y respuestas", "zh-Hans": "问答", "zh-Hant": "問答", "vi": "Hỏi và đáp", "ko": "질문과 답변"},
    "Ask a Question": {"es": "Hacer una pregunta", "zh-Hans": "提问", "zh-Hant": "提問", "vi": "Đặt câu hỏi", "ko": "질문하기"},
    "Type your question...": {"es": "Escribe tu pregunta...", "zh-Hans": "输入您的问题...", "zh-Hant": "輸入您的問題...", "vi": "Nhập câu hỏi của bạn...", "ko": "질문을 입력하세요..."},
    "No questions yet. Be the first to ask!": {"es": "Aún no hay preguntas. ¡Sé el primero en preguntar!", "zh-Hans": "还没有问题。成为第一个提问的人！", "zh-Hant": "還沒有問題。成為第一個提問的人！", "vi": "Chưa có câu hỏi nào. Hãy là người đầu tiên đặt câu hỏi!", "ko": "아직 질문이 없습니다. 첫 번째로 질문하세요!"},
    "Stay Connected": {"es": "Mantente conectado", "zh-Hans": "保持联系", "zh-Hant": "保持聯繫", "vi": "Giữ kết nối", "ko": "연결 유지"},
    
    # Leaderboard
    "All Members": {"es": "Todos los miembros", "zh-Hans": "所有成员", "zh-Hant": "所有成員", "vi": "Tất cả thành viên", "ko": "모든 구성원"},
    "Period": {"es": "Período", "zh-Hans": "期间", "zh-Hant": "期間", "vi": "Kỳ", "ko": "기간"},
    "Your Rank: #%lld": {"es": "Tu rango: #%lld", "zh-Hans": "您的排名：#%lld", "zh-Hant": "您的排名：#%lld", "vi": "Xếp hạng của bạn: #%lld", "ko": "순위: #%lld"},
    "🥇": {"es": "🥇", "zh-Hans": "🥇", "zh-Hant": "🥇", "vi": "🥇", "ko": "🥇"},
    "🥈": {"es": "🥈", "zh-Hans": "🥈", "zh-Hant": "🥈", "vi": "🥈", "ko": "🥈"},
    "🥉": {"es": "🥉", "zh-Hans": "🥉", "zh-Hant": "🥉", "vi": "🥉", "ko": "🥉"},
    "99+": {"es": "99+", "zh-Hans": "99+", "zh-Hant": "99+", "vi": "99+", "ko": "99+"},
    
    # Admin
    "Admin": {"es": "Administrador", "zh-Hans": "管理员", "zh-Hant": "管理員", "vi": "Quản trị viên", "ko": "관리자"},
    "Admin Panel": {"es": "Panel de administración", "zh-Hans": "管理面板", "zh-Hant": "管理面板", "vi": "Bảng quản trị", "ko": "관리자 패널"},
    "You don't have permission to access the admin panel.": {"es": "No tienes permiso para acceder al panel de administración.", "zh-Hans": "您没有访问管理面板的权限。", "zh-Hant": "您沒有存取管理面板的權限。", "vi": "Bạn không có quyền truy cập bảng quản trị.", "ko": "관리자 패널에 액세스할 권한이 없습니다."},
    "Access Denied": {"es": "Acceso denegado", "zh-Hans": "访问被拒绝", "zh-Hant": "存取被拒絕", "vi": "Truy cập bị từ chối", "ko": "액세스 거부됨"},
    "Verifying access...": {"es": "Verificando acceso...", "zh-Hans": "正在验证访问权限...", "zh-Hant": "正在驗證存取權限...", "vi": "Đang xác minh quyền truy cập...", "ko": "액세스 확인 중..."},
    "Management": {"es": "Gestión", "zh-Hans": "管理", "zh-Hant": "管理", "vi": "Quản lý", "ko": "관리"},
    "Pending Approvals": {"es": "Aprobaciones pendientes", "zh-Hans": "待审核", "zh-Hant": "待審核", "vi": "Chờ phê duyệt", "ko": "승인 대기"},
    "Loading pending users...": {"es": "Cargando usuarios pendientes...", "zh-Hans": "加载待审核用户中...", "zh-Hant": "載入待審核使用者中...", "vi": "Đang tải người dùng chờ phê duyệt...", "ko": "승인 대기 사용자 로딩 중..."},
    "User Details": {"es": "Detalles del usuario", "zh-Hans": "用户详情", "zh-Hant": "使用者詳情", "vi": "Chi tiết người dùng", "ko": "사용자 세부 정보"},
    "Approve": {"es": "Aprobar", "zh-Hans": "批准", "zh-Hant": "批准", "vi": "Phê duyệt", "ko": "승인"},
    "Approve User": {"es": "Aprobar usuario", "zh-Hans": "批准用户", "zh-Hant": "批准使用者", "vi": "Phê duyệt người dùng", "ko": "사용자 승인"},
    "Are you sure you want to approve this user? They will be able to access all app features.": {"es": "¿Estás seguro de que quieres aprobar a este usuario? Podrán acceder a todas las funciones de la aplicación.", "zh-Hans": "您确定要批准此用户吗？他们将能够访问所有应用功能。", "zh-Hant": "您確定要批准此使用者嗎？他們將能夠存取所有應用功能。", "vi": "Bạn có chắc muốn phê duyệt người dùng này không? Họ sẽ có thể truy cập tất cả tính năng của ứng dụng.", "ko": "이 사용자를 승인하시겠습니까? 모든 앱 기능에 액세스할 수 있게 됩니다."},
    "Reject": {"es": "Rechazar", "zh-Hans": "拒绝", "zh-Hant": "拒絕", "vi": "Từ chối", "ko": "거부"},
    "Reject User": {"es": "Rechazar usuario", "zh-Hans": "拒绝用户", "zh-Hant": "拒絕使用者", "vi": "Từ chối người dùng", "ko": "사용자 거부"},
    "Are you sure you want to reject this user? Their account will be deleted.": {"es": "¿Estás seguro de que quieres rechazar a este usuario? Su cuenta será eliminada.", "zh-Hans": "您确定要拒绝此用户吗？他们的账户将被删除。", "zh-Hant": "您確定要拒絕此使用者嗎？他們的帳戶將被刪除。", "vi": "Bạn có chắc muốn từ chối người dùng này không? Tài khoản của họ sẽ bị xóa.", "ko": "이 사용자를 거부하시겠습니까? 계정이 삭제됩니다."},
    "Make Admin": {"es": "Hacer administrador", "zh-Hans": "设为管理员", "zh-Hant": "設為管理員", "vi": "Đặt làm quản trị viên", "ko": "관리자로 지정"},
    "Are you sure you want to make this user an admin? They will have access to all admin features.": {"es": "¿Estás seguro de que quieres hacer administrador a este usuario? Tendrán acceso a todas las funciones de administración.", "zh-Hans": "您确定要将此用户设为管理员吗？他们将能够访问所有管理功能。", "zh-Hant": "您確定要將此使用者設為管理員嗎？他們將能夠存取所有管理功能。", "vi": "Bạn có chắc muốn đặt người dùng này làm quản trị viên không? Họ sẽ có quyền truy cập tất cả tính năng quản trị.", "ko": "이 사용자를 관리자로 지정하시겠습니까? 모든 관리자 기능에 액세스할 수 있게 됩니다."},
    "Remove Admin": {"es": "Quitar administrador", "zh-Hans": "移除管理员", "zh-Hant": "移除管理員", "vi": "Gỡ quản trị viên", "ko": "관리자 권한 제거"},
    "Are you sure you want to remove admin status from this user? They will lose access to admin features.": {"es": "¿Estás seguro de que quieres quitar el estado de administrador a este usuario? Perderán acceso a las funciones de administración.", "zh-Hans": "您确定要移除此用户的管理员状态吗？他们将失去对管理功能的访问权限。", "zh-Hant": "您確定要移除此使用者的管理員狀態嗎？他們將失去對管理功能的存取權限。", "vi": "Bạn có chắc muốn gỡ quyền quản trị viên của người dùng này không? Họ sẽ mất quyền truy cập các tính năng quản trị.", "ko": "이 사용자의 관리자 권한을 제거하시겠습니까? 관리자 기능에 대한 액세스 권한이 없어집니다."},
    "Loading members...": {"es": "Cargando miembros...", "zh-Hans": "加载成员中...", "zh-Hant": "載入成員中...", "vi": "Đang tải thành viên...", "ko": "구성원 로딩 중..."},
    "Unknown User": {"es": "Usuario desconocido", "zh-Hans": "未知用户", "zh-Hant": "未知使用者", "vi": "Người dùng không xác định", "ko": "알 수 없는 사용자"},
    "Quick Actions": {"es": "Acciones rápidas", "zh-Hans": "快速操作", "zh-Hant": "快速操作", "vi": "Hành động nhanh", "ko": "빠른 작업"},
    "Send Broadcast": {"es": "Enviar transmisión", "zh-Hans": "发送广播", "zh-Hant": "發送廣播", "vi": "Gửi thông báo", "ko": "브로드캐스트 보내기"},
    "Send Announcement": {"es": "Enviar anuncio", "zh-Hans": "发送公告", "zh-Hant": "發送公告", "vi": "Gửi thông báo", "ko": "공지 보내기"},
    "This will send an announcement to all approved users. Are you sure you want to proceed?": {"es": "Esto enviará un anuncio a todos los usuarios aprobados. ¿Estás seguro de que quieres continuar?", "zh-Hans": "这将向所有已批准的用户发送公告。您确定要继续吗？", "zh-Hant": "這將向所有已批准的用戶發送公告。您確定要繼續嗎？", "vi": "Điều này sẽ gửi thông báo cho tất cả người dùng đã được phê duyệt. Bạn có chắc muốn tiếp tục không?", "ko": "모든 승인된 사용자에게 공지가 전송됩니다. 계속하시겠습니까?"},
    "This will be sent to all approved users.": {"es": "Esto se enviará a todos los usuarios aprobados.", "zh-Hans": "这将发送给所有已批准的用户。", "zh-Hant": "這將發送給所有已批准的用戶。", "vi": "Điều này sẽ được gửi cho tất cả người dùng đã được phê duyệt.", "ko": "모든 승인된 사용자에게 전송됩니다."},
    "If enabled, the announcement will appear pinned at the top of users' notification feeds for 7 days.": {"es": "Si está habilitado, el anuncio aparecerá fijado en la parte superior de los feeds de notificaciones de los usuarios durante 7 días.", "zh-Hans": "如果启用，公告将在用户通知源顶部固定显示7天。", "zh-Hant": "如果啟用，公告將在使用者通知源頂部固定顯示7天。", "vi": "Nếu được bật, thông báo sẽ được ghim ở đầu nguồn cấp thông báo của người dùng trong 7 ngày.", "ko": "활성화되면 공지가 사용자 알림 피드 상단에 7일간 고정됩니다."},
    "Pin to notifications (7 days)": {"es": "Fijar a notificaciones (7 días)", "zh-Hans": "固定到通知（7天）", "zh-Hant": "固定到通知（7天）", "vi": "Ghim vào thông báo (7 ngày)", "ko": "알림에 고정 (7일)"},
    
    # Common phrases
    "Are you sure you want to sign out?": {"es": "¿Estás seguro de que quieres cerrar sesión?", "zh-Hans": "您确定要退出登录吗？", "zh-Hant": "您確定要登出嗎？", "vi": "Bạn có chắc muốn đăng xuất không?", "ko": "로그아웃하시겠습니까?"},
    "Refresh Status": {"es": "Actualizar estado", "zh-Hans": "刷新状态", "zh-Hant": "重新整理狀態", "vi": "Làm mới trạng thái", "ko": "상태 새로고침"},
    "Connect your Apple ID to sign in with Face ID/Touch ID": {"es": "Conecta tu ID de Apple para iniciar sesión con Face ID/Touch ID", "zh-Hans": "连接您的 Apple ID 以使用面容 ID/触控 ID 登录", "zh-Hant": "連接您的 Apple ID 以使用 Face ID/Touch ID 登入", "vi": "Kết nối ID Apple của bạn để đăng nhập bằng Face ID/Touch ID", "ko": "Apple ID를 연결하여 Face ID/Touch ID로 로그인"},
    "You'll be able to sign in with Apple Sign-In after linking your account.": {"es": "Podrás iniciar sesión con Apple Sign-In después de vincular tu cuenta.", "zh-Hans": "关联账户后，您将能够使用 Apple 登录。", "zh-Hant": "關聯帳戶後，您將能夠使用 Apple 登入。", "vi": "Sau khi liên kết tài khoản, bạn sẽ có thể đăng nhập bằng Apple Sign-In.", "ko": "계정을 연결한 후 Apple 로그인을 사용할 수 있습니다."},
    "Change the app's display language": {"es": "Cambiar el idioma de visualización de la aplicación", "zh-Hans": "更改应用的显示语言", "zh-Hant": "更改應用的顯示語言", "vi": "Thay đổi ngôn ngữ hiển thị của ứng dụng", "ko": "앱 표시 언어 변경"},
    "Ride and favor requests will appear here": {"es": "Las solicitudes de viaje y favor aparecerán aquí", "zh-Hans": "行程和帮助请求将显示在这里", "zh-Hant": "行程和幫助請求將顯示在這裡", "vi": "Yêu cầu đi xe và giúp đỡ sẽ hiển thị ở đây", "ko": "승차 및 도움 요청이 여기에 표시됩니다"},
    "Requests": {"es": "Solicitudes", "zh-Hans": "请求", "zh-Hant": "請求", "vi": "Yêu cầu", "ko": "요청"},
    
    # Format strings
    "Created %@": {"es": "Creado %@", "zh-Hans": "创建于 %@", "zh-Hant": "建立於 %@", "vi": "Đã tạo %@", "ko": "생성됨 %@"},
    "Error: %@": {"es": "Error: %@", "zh-Hans": "错误：%@", "zh-Hant": "錯誤：%@", "vi": "Lỗi: %@", "ko": "오류: %@"},
    
    # Special characters (keep as-is)
    "—": {"es": "—", "zh-Hans": "—", "zh-Hant": "—", "vi": "—", "ko": "—"},
    "99+": {"es": "99+", "zh-Hans": "99+", "zh-Hant": "99+", "vi": "99+", "ko": "99+"},
    "🥇": {"es": "🥇", "zh-Hans": "🥇", "zh-Hant": "🥇", "vi": "🥇", "ko": "🥇"},
    "🥈": {"es": "🥈", "zh-Hans": "🥈", "zh-Hant": "🥈", "vi": "🥈", "ko": "🥈"},
    "🥉": {"es": "🥉", "zh-Hans": "🥉", "zh-Hant": "🥉", "vi": "🥉", "ko": "🥉"},
}

def add_translations_to_string(string_key, string_data, translations_dict):
    """Add missing translations to a string entry"""
    if not string_key or string_key.startswith('%') or string_key.startswith('#'):
        return False  # Skip format strings
    
    # Get English value
    en_value = None
    if 'localizations' in string_data:
        if 'en' in string_data['localizations']:
            en_value = string_data['localizations']['en'].get('stringUnit', {}).get('value')
    
    # If no English value and no localizations, use key as English value
    if not en_value:
        en_value = string_key
    
    # Initialize localizations if needed
    if 'localizations' not in string_data:
        string_data['localizations'] = {}
    
    languages = ['es', 'zh-Hans', 'zh-Hant', 'vi', 'ko']
    
    # Add English if missing
    if 'en' not in string_data['localizations']:
        string_data['localizations']['en'] = {
            "stringUnit": {
                "state": "translated",
                "value": en_value
            }
        }
    
    # Add translations for each language
    for lang in languages:
        if lang not in string_data['localizations']:
            # Try to get translation from dictionary
            translation = translations_dict.get(en_value, {}).get(lang)
            if not translation:
                # If no translation found, use English as fallback
                translation = en_value
            
            string_data['localizations'][lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": translation
                }
            }
    
    return True

# Read the file
with open('NaarsCars/Resources/Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Process all strings
updated_count = 0
for key, value in data['strings'].items():
    if add_translations_to_string(key, value, TRANSLATIONS):
        updated_count += 1

print(f"Updated {updated_count} strings with translations")

# Write back
with open('NaarsCars/Resources/Localizable.xcstrings', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("✅ Translations added successfully!")
PYTHON_SCRIPT



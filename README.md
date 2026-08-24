# TraumaLink 360

ระบบบริหารการดูแลผู้บาดเจ็บตั้งแต่ Dispatch, Pre-hospital และ ER Command ไปจนถึง Trauma Registry และ PIPS โดยใช้ Supabase เป็นฐานข้อมูลกลาง

## ความสามารถหลัก

- เปิดดู Dashboard ได้โดยไม่ต้องเข้าสู่ระบบ โดยไม่เปิดเผยข้อมูลผู้ป่วย
- Supabase Auth บังคับเข้าสู่ระบบก่อนเข้าถึงรายชื่อผู้ป่วย รายละเอียดเคส และเมนูปฏิบัติงาน
- ฐานข้อมูล PostgreSQL พร้อม Row Level Security
- ซิงก์ข้อมูลทุกเมนูและรองรับ Realtime
- บันทึกเคสแบบ atomic ผ่าน RPC
- ล้างข้อมูลผู้ป่วยใน local cache เมื่อออกจากระบบ
- ส่งออกข้อมูล JSON, CSV และ Excel

## เริ่มใช้งาน

1. ติดตั้งสคีมาจาก `supabase/schema.sql` ใน Supabase SQL Editor
2. สร้างผู้ใช้เจ้าหน้าที่ใน Supabase Authentication
3. เปิดเว็บผ่าน HTTP server เช่น `python -m http.server 8765`
4. เข้า `http://127.0.0.1:8765/` เพื่อดู Dashboard หรือเข้าสู่ระบบด้วยบัญชีเจ้าหน้าที่เมื่อต้องการดูข้อมูลผู้ป่วย

รายละเอียดการติดตั้งฐานข้อมูลเพิ่มเติมอยู่ใน `supabase/README.md`

## ความปลอดภัย

- ฝั่งเว็บใช้ได้เฉพาะ Supabase publishable/anon key
- ห้ามใส่ secret key หรือ service-role key ในไฟล์เว็บ
- ตารางข้อมูลผู้ป่วยอนุญาตเฉพาะผู้ใช้ที่ผ่าน Supabase Auth ตามนโยบาย RLS
- Repository นี้ไม่มีข้อมูลผู้ป่วยตัวอย่างและไม่มีรหัสผ่านบัญชีเจ้าหน้าที่

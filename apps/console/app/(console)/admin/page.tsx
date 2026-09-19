import { redirect } from "next/navigation";

/** /admin -> C101 users (the admin section's first screen). */
export default function Page() {
  redirect("/admin/users");
}

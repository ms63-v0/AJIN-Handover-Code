/**
 * 화면 등록부. 새 화면을 추가하는 방법:
 *  1) pages/ 아래에 { id, title, render(root) → 정리함수 } 형태의 모듈을 만든다.
 *  2) 아래 PAGES 에 등록하고 config.js 의 NAV_ITEMS 에 같은 id의 메뉴를 추가한다.
 */
import { lotPage } from "./lot/index.js";
import { dashboardPage } from "./dashboard.js";
import { weldPage } from "./weld.js";
import { visionPage } from "./vision.js";
import { alarmPage } from "./alarm/index.js";
import { adminPage } from "./admin/index.js";

export const PAGES = {
  dashboard: dashboardPage,
  weld: weldPage,
  vision: visionPage,
  lot: lotPage,
  alarm: alarmPage,
  admin: adminPage,
};

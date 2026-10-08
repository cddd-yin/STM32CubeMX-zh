// STM32CubeMX 界面汉化 Agent（运行时翻译，不修改任何程序文件）
// 原理：通过 -javaagent 注入，周期性遍历 Swing 窗口/组件树，只把「显示文字」替换为中文。
//      不碰业务逻辑、不碰数据、不写任何文件，关掉即完全还原。
// 词典：与 agent jar 同目录的 zh.tsv（en<TAB>zh），可在程序运行时编辑、重启生效。
// 收集：加 -Dstm32zh.discover=true 时，把未翻译的可见文字追加到 发现-未翻译.tsv，供补词库。
import java.awt.Component;
import java.awt.Container;
import java.awt.Dialog;
import java.awt.Frame;
import java.awt.Window;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentLinkedQueue;
import javax.swing.AbstractButton;
import javax.swing.JComponent;
import javax.swing.JDialog;
import javax.swing.JFrame;
import javax.swing.JInternalFrame;
import javax.swing.JLabel;
import javax.swing.JTabbedPane;
import javax.swing.JTable;
import javax.swing.SwingUtilities;
import javax.swing.border.Border;
import javax.swing.border.TitledBorder;
import javax.swing.table.JTableHeader;

public final class Stm32CubeMxZhAgent {

    private static final Map<String, String> DICT = new LinkedHashMap<>();
    private static final Map<String, String> DICT_TRIMMED = new LinkedHashMap<>();
    private static final Map<String, String> PHRASES = new LinkedHashMap<>();
    private static final Set<String> SEEN = Collections.synchronizedSet(new LinkedHashSet<String>());
    private static final ConcurrentLinkedQueue<String> NEW_STRINGS = new ConcurrentLinkedQueue<>();
    private static volatile boolean discover = false;
    private static volatile boolean debug = false;
    private static File baseDir = new File(".");

    public static void premain(String agentArgs, java.lang.instrument.Instrumentation inst) {
        try {
            baseDir = resolveBaseDir();
            discover = "true".equalsIgnoreCase(System.getProperty("stm32zh.discover"));
            debug = "true".equalsIgnoreCase(System.getProperty("stm32zh.debug"));
            loadDict(new File(baseDir, "zh.tsv"));
            log("premain baseDir=" + baseDir + " discover=" + discover + " dict=" + DICT.size());
            if (discover) { startDiscoveryWriter(); }
            Thread t = new Thread(new Runnable() {
                public void run() {
                    while (true) {
                        try { SwingUtilities.invokeLater(new Runnable() { public void run() { onePass(); } }); }
                        catch (Throwable ignore) { }
                        try { Thread.sleep(400); } catch (InterruptedException e) { return; }
                    }
                }
            }, "stm32zh-translator");
            t.setDaemon(true);
            t.start();
            log("translator thread started, alive=" + t.isAlive());
        } catch (Throwable t) {
            // 任何异常都不能影响主程序
            try {
                FileWriter w = new FileWriter(new File(baseDir, "agent-error.txt"), true);
                w.write(new java.util.Date() + " premain 失败：" + t + "\r\n");
                for (StackTraceElement e : t.getStackTrace()) { w.write("    at " + e + "\r\n"); }
                w.close();
            } catch (Throwable ignore) { }
        }
    }

    // ---------- 词典 ----------

    private static File resolveBaseDir() {
        try {
            File f = new File(Stm32CubeMxZhAgent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            if (f.isFile()) { return f.getParentFile(); }
            return f;
        } catch (Throwable t) {
            return new File(".");
        }
    }

    private static void loadDict(File f) {
        if (f == null || !f.isFile()) { return; }
        BufferedReader r = null;
        try {
            r = new BufferedReader(new InputStreamReader(new FileInputStream(f), StandardCharsets.UTF_8));
            String line;
            while ((line = r.readLine()) != null) {
                if (line.isEmpty() || line.charAt(0) == '#') { continue; }
                int tab = line.indexOf('\t');
                if (tab <= 0) { continue; }
                String en = line.substring(0, tab);
                String zh = line.substring(tab + 1).trim();
                if (en.startsWith("*")) {
                    // 短语替换（仅用于窗口标题，如 *Untitled<TAB>未命名）
                    PHRASES.put(en.substring(1), zh);
                    continue;
                }
                DICT.put(en, zh);
                String t = en.trim();
                if (!t.equals(en)) { DICT_TRIMMED.put(t, zh); }
            }
        } catch (Throwable ignore) {
        } finally {
            try { if (r != null) { r.close(); } } catch (Throwable ignore) { }
        }
    }

    private static String tr(String s) {
        if (s == null || s.isEmpty()) { return s; }
        String v = DICT.get(s);
        if (v != null) { return v.isEmpty() ? s : v; }
        String t = s.trim();
        if (!t.isEmpty() && !t.equals(s)) {
            v = DICT.get(t);
            if (v != null) { return v.isEmpty() ? s : v; }
        }
        // HTML 文案：逐段翻译标签外的文字，标签原样保留
        String low = t.toLowerCase();
        if (low.startsWith("<html")) {
            return trHtml(s);
        }
        int n = t.length();
        // 去掉结尾的冒号/省略号后重试（保留原结尾符号）
        if (n > 3 && (t.endsWith(":") || t.endsWith("..."))) {
            String core = t.endsWith("...") ? t.substring(0, n - 3) : t.substring(0, n - 1);
            String tail = t.substring(core.length());
            v = DICT.get(core);
            if (v == null) { v = DICT_TRIMMED.get(core); }
            if (v != null) { return v + tail; }
        }
        return s;
    }

    // 把 HTML 文案里标签之外的文字逐段翻译（例如 <html><br>Existing Projects<br></html>）
    private static String trHtml(String s) {
        StringBuilder out = new StringBuilder();
        StringBuilder text = new StringBuilder();
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            if (c == '<') {
                if (text.length() > 0) { out.append(trPlain(text.toString())); text.setLength(0); }
                int close = s.indexOf('>', i);
                if (close < 0) { out.append(s.substring(i)); break; }
                out.append(s, i, close + 1);
                i = close + 1;
            } else {
                text.append(c);
                i++;
            }
        }
        if (text.length() > 0) { out.append(trPlain(text.toString())); }
        return out.toString();
    }

    // 仅按词典替换（不做 trim 以外处理），保留原有空白
    private static String trPlain(String s) {
        if (s == null || s.isEmpty()) { return s; }
        String v = DICT.get(s);
        if (v != null) { return v.isEmpty() ? s : v; }
        String t = s.trim();
        if (t.isEmpty()) { return s; }
        v = DICT.get(t);
        if (v == null) { v = DICT_TRIMMED.get(t); }
        if (v != null) {
            int a = s.indexOf(t);
            return s.substring(0, a) + v + s.substring(a + t.length());
        }
        return s;
    }

    // ---------- 翻译一轮 ----------

    private static void onePass() {
        try {
            if (debug) { log("onePass 开始"); }
            Set<Component> visited = Collections.newSetFromMap(new IdentityHashMap<Component, Boolean>());
            int total = 0, windows = 0;
            for (Window w : Window.getWindows()) {
                if (w == null) { continue; }
                total++;
                if (!w.isVisible()) { continue; }
                windows++;
                translateWindow(w, visited);
            }
            if (debug) { log("onePass 总窗口=" + total + " 可见=" + windows + " visited=" + visited.size() + " discovered=" + SEEN.size() + " 线程组=" + Thread.currentThread().getThreadGroup().getName()); }
        } catch (Throwable ignore) {
            // 单轮失败不影响后续
        }
    }

    private static String trTitle(String s) {
        String r = tr(s);
        if (r == null || PHRASES.isEmpty()) { return r; }
        for (Map.Entry<String, String> e : PHRASES.entrySet()) {
            if (r.contains(e.getKey())) { r = r.replace(e.getKey(), e.getValue()); }
        }
        return r;
    }

    private static void translateWindow(Window w, Set<Component> visited) {
        if (w instanceof JFrame) {
            JFrame f = (JFrame) w;
            note(f.getTitle());
            String t = trTitle(f.getTitle());
            if (t != null && !t.equals(f.getTitle())) { f.setTitle(t); }
        } else if (w instanceof JDialog) {
            JDialog d = (JDialog) w;
            note(d.getTitle());
            String t = trTitle(d.getTitle());
            if (t != null && !t.equals(d.getTitle())) { d.setTitle(t); }
        } else if (w instanceof Frame) {
            Frame f = (Frame) w;
            String t = trTitle(f.getTitle());
            if (t != null && !t.equals(f.getTitle())) { f.setTitle(t); }
        } else if (w instanceof Dialog) {
            Dialog d = (Dialog) w;
            String t = trTitle(d.getTitle());
            if (t != null && !t.equals(d.getTitle())) { d.setTitle(t); }
        }
        walk(w, visited);
    }

    private static void walk(Component c, Set<Component> visited) {
        if (c == null || !visited.add(c)) { return; }
        try {
            if (c instanceof JComponent) {
                JComponent jc = (JComponent) c;
                String tip = jc.getToolTipText();
                if (tip != null && !tip.isEmpty()) {
                    note(tip);
                    String t = tr(tip);
                    if (t != null && !t.equals(tip)) { jc.setToolTipText(t); }
                }
                Border b = jc.getBorder();
                if (b instanceof TitledBorder) {
                    TitledBorder tb = (TitledBorder) b;
                    String tt = tb.getTitle();
                    if (tt != null && !tt.isEmpty()) {
                        note(tt);
                        String t = tr(tt);
                        if (t != null && !t.equals(tt)) { tb.setTitle(t); }
                    }
                }
                JComponent pop = jc.getComponentPopupMenu();
                if (pop != null) { walk(pop, visited); }
            }
            if (c instanceof AbstractButton) {
                AbstractButton btn = (AbstractButton) c;
                String txt = btn.getText();
                if (txt != null && !txt.isEmpty()) {
                    note(txt);
                    String t = tr(txt);
                    if (t != null && !t.equals(txt)) { btn.setText(t); }
                }
            } else if (c instanceof JLabel) {
                JLabel lab = (JLabel) c;
                String txt = lab.getText();
                if (txt != null && !txt.isEmpty()) {
                    note(txt);
                    String t = tr(txt);
                    if (t != null && !t.equals(txt)) { lab.setText(t); }
                }
            }
            if (c instanceof javax.swing.JMenu) {
                // 菜单项挂在弹出菜单里，不在组件子节点中，需显式遍历
                javax.swing.JPopupMenu pm = ((javax.swing.JMenu) c).getPopupMenu();
                if (pm != null) { walk(pm, visited); }
            }
            if (c instanceof JTabbedPane) {
                JTabbedPane tp = (JTabbedPane) c;
                for (int i = 0; i < tp.getTabCount(); i++) {
                    String txt = tp.getTitleAt(i);
                    if (txt != null && !txt.isEmpty()) {
                        note(txt);
                        String t = tr(txt);
                        if (t != null && !t.equals(txt)) { tp.setTitleAt(i, t); }
                    }
                }
            }
            if (c instanceof JTable) {
                JTable table = (JTable) c;
                JTableHeader h = table.getTableHeader();
                if (h != null) {
                    for (int i = 0; i < h.getColumnModel().getColumnCount(); i++) {
                        String txt = String.valueOf(h.getColumnModel().getColumn(i).getHeaderValue());
                        if (txt != null && !txt.isEmpty() && !"null".equals(txt)) {
                            note(txt);
                            String t = tr(txt);
                            if (t != null && !t.equals(txt)) {
                                h.getColumnModel().getColumn(i).setHeaderValue(t);
                            }
                        }
                    }
                    h.repaint();
                }
            }
            if (c instanceof JInternalFrame) {
                JInternalFrame f = (JInternalFrame) c;
                String txt = f.getTitle();
                if (txt != null && !txt.isEmpty()) {
                    note(txt);
                    String t = tr(txt);
                    if (t != null && !t.equals(txt)) { f.setTitle(t); }
                }
            }
        } catch (Throwable ignore) {
            // 单个组件失败不影响其它
        }
        if (c instanceof Container) {
            try {
                for (Component child : ((Container) c).getComponents()) { walk(child, visited); }
            } catch (Throwable ignore) { }
        }
    }

    // ---------- 收集未翻译条目 ----------

    private static void note(String s) {
        if (!discover || s == null) { return; }
        String t = s.trim();
        if (t.length() < 2 || t.length() > 150) { return; }
        if (DICT.containsKey(s) || DICT.containsKey(t)) { return; }
        if (!looksTranslatable(t)) { return; }
        if (SEEN.add(t)) { NEW_STRINGS.add(t); }
    }

    private static boolean looksTranslatable(String t) {
        boolean hasLetter = false;
        for (int i = 0; i < t.length(); i++) {
            char c = t.charAt(i);
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) { hasLetter = true; break; }
        }
        if (!hasLetter) { return false; }
        if (t.contains("\n") || t.contains("\r")) { return false; }
        if (t.contains("://") || t.contains("@")) { return false; }
        String low = t.toLowerCase();
        if (low.startsWith("http") || low.startsWith("www.")) { return false; }
        if (low.matches(".*\\.(jar|exe|dll|zip|c|h|cpp|ioc|txt|xml|json|elf|bin|hex|html|pdf|png|ico)$")) { return false; }
        if (low.startsWith("c:\\") || low.startsWith("c:/") || low.startsWith("\\")) { return false; }
        return true;
    }

    private static void startDiscoveryWriter() {
        Thread t = new Thread(new Runnable() {
            public void run() {
                while (true) {
                    try { Thread.sleep(5000); } catch (InterruptedException e) { return; }
                    flushNewStrings();
                }
            }
        }, "stm32zh-discovery");
        t.setDaemon(true);
        t.start();
    }

    private static synchronized void log(String s) {
        if (!debug) { return; }
        FileWriter w = null;
        try {
            w = new FileWriter(new File(baseDir, "agent-log.txt"), true);
            w.write(new java.util.Date() + " " + s + "\r\n");
        } catch (Throwable ignore) {
        } finally {
            try { if (w != null) { w.close(); } } catch (Throwable ignore) { }
        }
    }

    private static synchronized void flushNewStrings() {
        if (NEW_STRINGS.isEmpty()) { return; }
        log("flushNewStrings 待写=" + NEW_STRINGS.size());
        FileWriter w = null;
        try {
            File f = new File(baseDir, "发现-未翻译.tsv");
            boolean fresh = !f.exists();
            w = new FileWriter(f, true);
            if (fresh) { w.write("# 自动收集的未翻译界面文字（UTF-8）。翻译后追加到 zh.tsv 即可。\r\n"); }
            String s;
            int n = 0;
            while ((s = NEW_STRINGS.poll()) != null && n < 200) {
                w.write(s + "\t\r\n");
                n++;
            }
        } catch (Throwable ignore) {
        } finally {
            try { if (w != null) { w.close(); } } catch (Throwable ignore) { }
        }
    }
}

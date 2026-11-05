# 上传本地版本到GitHub

截图已有仓库：`https://github.com/AllenXu-weihao/-0`。这里仅上传MIMO_v2_matlab实验包，不上传整个星地通信文件夹。

1. 在本目录打开PowerShell。执行 `git status`，确认工作树干净；`git log -1 --oneline` 查看已提交版本。
2. 如果继续使用截图里的空仓库，执行：

```powershell
git remote add origin https://github.com/AllenXu-weihao/-0.git
git push -u origin main
```

如果已有origin，先 `git remote -v` 核对地址，不重复add。若你在网页重命名了仓库，将命令URL改为新地址。仓库名建议mimo-v2-matlab，中文名称可写Description。

3. 按Git弹出的浏览器流程登录。不要把密码或token发给助手，也不要写进工程文件。
4. 刷新GitHub仓库，确认README、MIMO.m、deployment.mat和experiments均出现；核对页面commit与本地一致。

如果Git提示远端已有提交，不执行force；先保存报错并检查差异。截图仓库是Public，执行push会公开这些文件；若只供自己研究可先在GitHub将仓库改为Private。

后续更新：`git status` → 明确选择文件 `git add 文件名` → `git commit -m "说明本次变更"` → `git push`。测试结果先精选报告再决定纳入版本，默认忽略大结果目录。

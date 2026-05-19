# 应用图标

只维护这一张图即可：

```
Resources/Icons/FractalForge.png
```

## 为什么之前有 install 脚本？

Xcode 的 **App Icon** 只能读取 `Assets.xcassets/AppIcon.appiconset/` **里面的** PNG，不能直接引用外面的路径。  
脚本只是为了把外面的图复制进 appiconset——确实多此一举。

## 现在怎么做（二选一，都不用脚本）

### 方式 A：在 Xcode 里拖一次（推荐）

1. 打开 `Assets.xcassets` → **AppIcon**
2. 把 `Resources/Icons/FractalForge.png` **拖进** 1024 图标槽
3. 以后只替换 `Resources/Icons/FractalForge.png`，再在 AppIcon 里重新拖一次（或方式 B）

### 方式 B：软链接（改图自动生效，只需配置一次）

```bash
cd ~/Documents/FractalForge
ln -sf ../../../Resources/Icons/FractalForge.png \
  FractalForge/Assets.xcassets/AppIcon.appiconset/FractalForge.png
```

之后只改 `Resources/Icons/FractalForge.png`，**⌘B** 即可。

已删除 `install_icons.sh` 和所有构建脚本。

SHELL := /bin/bash
HOMEDIR := /home/$(USER)
AHK_BIN := /mnt/c/Program\ Files/AutoHotkey/Compiler/Ahk2Exe.exe
DOCDIR := /mnt/f/OneDrive/Documents
LIBDIR := $(DOCDIR)/AutoHotkey/Lib
SCRIPTDIR := /mnt/c/scripts
APP := UIA_Inspector
VER := 
APPEXE := $(APP)$(VER).exe
SETTINGSFILE := $(APP)_settings.ini
TARGET_EXE := $(SCRIPTDIR)/$(APPEXE)
TARGET_SETTINGSFILE := $(SCRIPTDIR)/$(SETTINGSFILE)
SRC := $(APP).ahk
# Destination for lib/ and res/ under the AHK Lib folder
DESTLIBDIR := $(LIBDIR)/$(APP)
# Source directories to install
LIB_SRC := lib
RES_SRC := res
# Read include files from includes.txt (empty on first run, populated on second)
INCLUDES := $(shell cat includes.txt 2>/dev/null)

.PHONY: all build install clean force-install lib-install

all: $(TARGET_EXE)

build: lib-install $(APPEXE)

# Main exe depends on lib-install, source, includes.txt, and all included files
# lib-install must run first so the compiler can resolve #Include <UIA_Inspector\...> directives
$(APPEXE): lib-install $(SRC) includes.txt $(shell cat includes.txt 2>/dev/null)
	@echo Killing any running $(APPEXE)...
	-@/mnt/c/Windows/System32/taskkill.exe /f /im $(APPEXE) 2>/dev/null || true
	$(AHK_BIN) /in $(SRC) /out $(APPEXE)
	@echo build completed at $$(date)

# Install target - triggered by exe changes
$(TARGET_EXE): $(APPEXE)
	@if [ ! -f $@ ]; then \
		$(MAKE) --no-print-directory force-install; \
	else \
		$(MAKE) --no-print-directory install; \
	fi

# Generate/update includes.txt - depends on source so it regenerates when source changes
# Always checks if library files have changed, only touches file if content actually changed
includes.txt: $(SRC)
	@$(HOMEDIR)/bin/makeincludes --output $@.tmp && \
	if [ -f $@ ] && cmp -s $@.tmp $@; then \
		rm $@.tmp; \
	else \
		mv $@.tmp $@; \
	fi

# Install lib/ and res/ contents to DESTLIBDIR/UIA_Inspector/
lib-install:
	@mkdir -p $(DESTLIBDIR)
	@echo Installing lib files to $(DESTLIBDIR)...
	@rsync -av --update --info=NAME $(LIB_SRC)/ $(DESTLIBDIR)/
	@echo Installing res files to $(DESTLIBDIR)...
	@rsync -av --update --info=NAME $(RES_SRC)/ $(DESTLIBDIR)/
	@echo lib-install completed at $$(date)

local-install: lib-install
	@echo Installing $(APPEXE) to local directory
	@cp -vf $(APPEXE) $(TARGET_EXE)
	@if [ ! -f $(TARGET_SETTINGSFILE) ] || [ $(SETTINGSFILE) -nt $(TARGET_SETTINGSFILE) ]; then \
		cp -vf $(SETTINGSFILE) $(TARGET_SETTINGSFILE); \
	fi
	@echo local-install completed at $$(date)

install: local-install
	@echo install completed at $$(date)

force-install: lib-install
	@echo Installing $(APPEXE) to local directory
	@cp -vf $(APPEXE) $(TARGET_EXE)
	@cp -vf $(SETTINGSFILE) $(TARGET_SETTINGSFILE)
	@echo force-install completed at $$(date)

clean:
	@rm -vf $(APPEXE)
	@rm -vf $(TARGET_EXE)
	@echo Removing lib files from $(DESTLIBDIR)...
	@find $(DESTLIBDIR) -maxdepth 1 -type f -exec echo Deleting: {} \; -exec rm -vf {} +
	@for dir in Scintilla; do \
		if [ -d $(DESTLIBDIR)/$$dir ]; then \
			echo Removing $(DESTLIBDIR)/$$dir...; \
			rm -rf $(DESTLIBDIR)/$$dir; \
		fi \
	done
	@rm -vf $(TARGET_SETTINGSFILE)
	@rm -vf includes.txt
	@echo clean completed at $$(date)

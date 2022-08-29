Summary: openEuler Security Tool
Name   : security-tool
Version: 2.0
Release: 1.50
Source0: %{name}-%{version}.tar.bz2
Source1: security
Source2: security.conf
Source3: security-tool.sh
Source4: openEuler-security.service
Source5: usr-security.conf
License: Mulan PSL v2
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires: bash setup pam util-linux binutils sudo crontabs cronie 
Requires: shadow initscripts ca-certificates openssh rsyslog dbus-daemon
Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units
BuildRequires: xauth

%description
openEuler Security Tool

%global debug_package %{nil}

%prep
%setup -q

%build

%check

%install
rm -rf $RPM_BUILD_ROOT
install -d -m0700 $RPM_BUILD_ROOT%{_sysconfdir}/openEuler_security
install -m0600 %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/openEuler_security/security
install -m0400 %{SOURCE2} $RPM_BUILD_ROOT%{_sysconfdir}/openEuler_security/security.conf
install -m0600 %{SOURCE5} $RPM_BUILD_ROOT%{_sysconfdir}/openEuler_security/usr-security.conf
install -d -m0755 $RPM_BUILD_ROOT/%{_unitdir}
install -m0644 %{SOURCE4} $RPM_BUILD_ROOT/%{_unitdir}/openEuler-security.service
install -d -m0755 $RPM_BUILD_ROOT/%{_sbindir}
install -m0500 %{SOURCE3} $RPM_BUILD_ROOT/%{_sbindir}/security-tool.sh
install -m0644 csh.precmd $RPM_BUILD_ROOT%{_sysconfdir}/csh.precmd
install -d -m0755 $RPM_BUILD_ROOT/%{_sysconfdir}/profile.d
install -d -m0755 $RPM_BUILD_ROOT/%{_sysconfdir}/pam.d
install -m0644 password-auth-crond $RPM_BUILD_ROOT%{_sysconfdir}/pam.d/password-auth-crond
install -m0644 su-local $RPM_BUILD_ROOT%{_sysconfdir}/pam.d/su-local

%clean
rm -rf $RPM_BUILD_ROOT

%pre

%post
sed -i 's/system-auth$/password-auth-crond/g' /etc/pam.d/crond

if [ $1 -ge 2 ]
then
    sed -i 's/readonly HISTSIZE$//g' /etc/profile
    sed -i 's/readonly TMOUT$//g' /etc/profile
fi

if [ -h /etc/pam.d/su ]
then
    rm -f /etc/pam.d/su
else
    mv -f /etc/pam.d/su /etc/pam.d/su-bak
fi
ln -s /etc/pam.d/su-local /etc/pam.d/su

%systemd_post openEuler-security.service
systemctl enable openEuler-security.service

%preun
%systemd_preun openEuler-security.service
if [ $1 -eq 0 ]
then
    sed -i 's/password-auth-crond$/system-auth/g' /etc/pam.d/crond
fi

%postun
%systemd_postun_with_restart openEuler-security.service

if [ $1 -eq 0 ]
then

    if [ -f /etc/pam.d/su-bak ]
    then
        mv -f /etc/pam.d/su-bak /etc/pam.d/su
    fi

    if [ -f /etc/pam.d/password-auth-ac ]
    then
        rm -f /etc/pam.d/password-auth
        ln -s /etc/pam.d/password-auth-ac /etc/pam.d/password-auth
    elif [ -f /etc/pam.d/password-auth-bak ]
    then
        mv -f /etc/pam.d/password-auth-bak /etc/pam.d/password-auth
    fi

    if [ -f /etc/pam.d/system-auth-ac ]
    then
        rm -f /etc/pam.d/system-auth
        ln -s /etc/pam.d/system-auth-ac /etc/pam.d/system-auth
    elif [ -f /etc/pam.d/system-auth-bak ]
    then
        mv -f /etc/pam.d/system-auth-bak /etc/pam.d/system-auth
    fi
fi

%files
%defattr(-,root,root)
%attr(0700,root,root) %dir %{_sysconfdir}/openEuler_security
%attr(0600,root,root) %config(noreplace) %{_sysconfdir}/openEuler_security/security
%attr(0400,root,root) %config %{_sysconfdir}/openEuler_security/security.conf
%attr(0600,root,root) %config %{_sysconfdir}/openEuler_security/usr-security.conf
%attr(0644,root,root) %{_sysconfdir}/csh.precmd
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/pam.d/password-auth-crond
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/pam.d/su-local
%attr(0644,root,root) %{_unitdir}/openEuler-security.service
%attr(0500,root,root) %{_sbindir}/security-tool.sh

%changelog
* Mon Aug 29 2022 zhengxiaoxiao <zhengxiaoxiao2@huawei.com> - 2.0-1.50
- fix sed keyword error in /etc/pam.d/crond

* Mon Oct 12 2020 gaoyusong <gaoyusong1@huawei.com> - 2.0-1.49
- Use secure MACs and KexAlgorithms

* Fri Jul 3 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.48
- rm zzz_openEuler_history.sh

* Fri May 29 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.47
- Move -- befora path

* Fri May 29 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.46
- Do not set umask to 077 any more

* Thu May 7 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.45
- Update LICENSE of files

* Wed Apr 29 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.44
- Update LICENSE to Mulan PSL v2.0

* Fri Feb 21 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.43
- Allow wheel group to use sudo by default

* Wed Jan 22 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.42
- Fix problems of script caused by "*" and multiple spaces

* Wed Jan 22 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.41
- Fix the problem of dbus-daemon-launch-helper's group 

* Sun Jan 12 2020 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.40
- Delete password-auth-local and system-auth-local

* Sun Dec 29 2019 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.39
- Add copyright for su-local

* Thu Dec 19 2019 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.38
- Delete unused infomation

* Mon Nov 11 2019 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.37
- Modify License

* Mon Sep 25 2019 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.36
- Add requires

* Mon Sep 16 2019 openEuler Buildteam <buildteam@openEuler.org> - 2.0-1.35
- Package init for openEuler
